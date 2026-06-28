const std = @import("std");
const log = std.log.scoped(.asset_loader);
const assert = std.debug.assert;
const zm = @import("zmath");
const Gltf = @import("zgltf").Gltf;

const Engine = @import("vulkan/engine.zig");
const Sampler = @import("vulkan/sampler.zig");
const Mesh = @import("vulkan/mesh.zig");
const Image = @import("vulkan/image.zig");
const Buffer = @import("vulkan/buffer.zig");
const MetallicRoughness = @import("graphics/materials.zig").MetallicRoughness;
const MaterialPass = @import("graphics/materials.zig").MaterialPass;

const Config = @import("../config.zig");
const Scene = @import("graphics/scene.zig");
const LoadedGLTF = Scene.LoadedGLTF;
const BasicNode = Scene.BasicNode;
const MeshNode = Scene.MeshNode;
const IRenderable = Scene.IRenderable;
const Vertex = @import("graphics/buffers.zig").Vertex;

const AssetManager = @This();

const MAX_FILE_SIZE = 512_000_000_000;

const ImageCached = struct {
    image: Image,
    sampler: Sampler,
};

io: std.Io,
allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

meshes: std.ArrayList(Mesh),
nodes: std.ArrayList(IRenderable),
materials: std.ArrayList(Mesh.GLTFMaterial),
images: std.ArrayList(Image),

image_cache: std.ArrayList(ImageCached),

pub fn init(allocator: std.mem.Allocator, io: std.Io) !AssetManager {
    return .{
        .io = io,
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .materials = .empty,
        .meshes = .empty,
        .nodes = .empty,
        .image_cache = .empty,
        .images = .empty,
    };
}

pub fn deinit(self: *AssetManager, engine: *const Engine) void {
    for (self.meshes.items) |*mesh| {
        mesh.destroy(engine.ctx);
    }
    self.meshes.deinit(self.allocator);

    self.nodes.deinit(self.allocator);
    self.materials.deinit(self.allocator);

    for (self.images.items) |*img| {
        img.destroy(engine.ctx);
    }

    self.image_cache.deinit(self.allocator);
    self.images.deinit(self.allocator);
}

pub fn loadGLTFAsset(self: *AssetManager, engine: *Engine, filename: []const u8) !LoadedGLTF {
    var gltf = Gltf.init(self.allocator);
    defer gltf.deinit();

    const extension = std.fs.path.extension(filename);

    if (std.mem.eql(u8, extension, ".glb") or std.mem.eql(u8, extension, ".gltf")) {
        const cwd = std.Io.Dir.cwd();
        const buffer = try cwd.readFileAllocOptions(self.io, filename, self.allocator, std.Io.Limit.limited(MAX_FILE_SIZE), .@"4", null);
        try gltf.parse(buffer);
    } else {
        return error.FileNotSupported;
    }

    if (null == gltf.glb_binary) return error.GlbBinaryEmpty;
    const glb_binary = gltf.glb_binary.?;

    var loaded_gltf: LoadedGLTF = try LoadedGLTF.init(self.allocator);
    loaded_gltf.creator = engine;

    const initial_mesh_index = self.meshes.items.len;
    const initial_node_index = self.nodes.items.len;
    const initial_material_index = self.materials.items.len;
    try self.meshes.ensureTotalCapacity(self.allocator, initial_mesh_index + gltf.data.meshes.len);
    try self.nodes.ensureTotalCapacity(self.allocator, initial_node_index + gltf.data.nodes.len);
    try self.materials.ensureTotalCapacity(self.allocator, initial_material_index + gltf.data.materials.len);

    loaded_gltf.descriptor_pool = try .init(self.allocator, engine.ctx, @intCast(gltf.data.materials.len), &.{
        .{ .vk_type = .combined_image_sampler, .ratio = 3 },
        .{ .vk_type = .uniform_buffer, .ratio = 3 },
        .{ .vk_type = .storage_buffer, .ratio = 1 },
    });

    // Load Samplers
    for (gltf.data.samplers) |*samp| {
        const mag_filter = extractFilter(samp.mag_filter orelse .nearest);
        const mipmap_mode = extractMipmapMode(samp.min_filter orelse .nearest);

        const sampler_option: Sampler.SamplerOption = .{
            .min_filter = mipmap_mode,
            .mag_filter = mag_filter,
            .mipmap_mode = mipmap_mode,
            .max_lod = 1000,
            .min_lod = 0,
        };

        const sampler = try Sampler.create(engine.ctx, sampler_option);
        try loaded_gltf.samplers.append(self.allocator, sampler);
    }

    const current_img_idx = self.images.items.len;
    try self.images.ensureTotalCapacity(self.allocator, current_img_idx + gltf.data.images.len);

    const bindless_slots = try self.allocator.alloc(u32, gltf.data.images.len);
    defer self.allocator.free(bindless_slots);

    if (Config.log.mesh) {
        log.info("[DBG] GLTF images: {d}, materials: {d}, textures: {d}", .{ gltf.data.images.len, gltf.data.materials.len, gltf.data.textures.len });
    }

    // Load Textures
    for (gltf.data.images, 0..) |*img, i| {
        const name = img.name orelse "";

        const image = if (img.uri) |uri| blk: {
            if (Config.log.mesh) {
                log.info("[DBG] image[{d}] uri={s}", .{ i, uri });
            }
            break :blk try Image.createFromPath(engine, uri, .packed_rgba_8_8_8_8, .{ .sampled_bit = true });
        } else if (img.data) |bytes| blk: {
            if (Config.log.mesh) {
                log.info("[DBG] image[{d}] embedded {d} bytes mime={?s}", .{ i, bytes.len, img.mime_type });
            }
            break :blk try Image.createFromBytesWithSDL(engine, bytes, .{ .sampled_bit = true });
        } else blk: {
            if (Config.log.mesh) {
                log.warn("[DBG] image[{d}] MISSING — using error_checker", .{i});
            }
            break :blk engine.images.get(.error_checker);
        };

        self.images.appendAssumeCapacity(image);
        bindless_slots[i] = try engine.registerTexture(self.images.items[current_img_idx + i], engine.samplers.get(.linear));
        if (Config.log.mesh) {
            log.info("[DBG] image[{d}] '{s}' → bindless slot {d}", .{ i, name, bindless_slots[i] });
        }
        try loaded_gltf.images.put(self.allocator, name, &self.images.items[current_img_idx + i]);
    }

    loaded_gltf.material_data_buffer = try MetallicRoughness.createMaterialPushConstantsBuffer(engine, @intCast(gltf.data.materials.len));

    const scene_material_constants = try self.allocator.alloc(MetallicRoughness.MaterialConstants, gltf.data.materials.len);
    defer self.allocator.free(scene_material_constants);

    // Load Materials
    for (gltf.data.materials, 0..) |mat, i| {
        const name = mat.name orelse "";
        var new_mat: Mesh.GLTFMaterial = undefined;

        const pass_type: MaterialPass = if (mat.alpha_mode == .blend) .Transparent else .MainColor;

        var material_resources: MetallicRoughness.MaterialResources = .{
            .color_image = engine.images.get(.white),
            .color_sampler = engine.samplers.get(.linear),
            .metal_rough_image = engine.images.get(.white),
            .metal_rough_sampler = engine.samplers.get(.linear),
            .data_buffer = loaded_gltf.material_data_buffer,
            .data_buffer_offset = i * @sizeOf(MetallicRoughness.MaterialConstants),
        };

        if (mat.metallic_roughness.base_color_texture) |tex_info| {
            const texture = gltf.data.textures[tex_info.index];
            if (texture.source) |img_idx| {
                material_resources.color_image = self.images.items[current_img_idx + img_idx];
            }

            if (texture.sampler) |sampler_idx| {
                material_resources.color_sampler = loaded_gltf.samplers.items[sampler_idx];
            }
        }

        if (mat.metallic_roughness.metallic_roughness_texture) |tex_info| {
            const texture = gltf.data.textures[tex_info.index];
            if (texture.source) |img_idx| {
                material_resources.metal_rough_image = self.images.items[current_img_idx + img_idx];
            }

            if (texture.sampler) |sampler_idx| {
                material_resources.metal_rough_sampler = loaded_gltf.samplers.items[sampler_idx];
            }
        }

        const color_tex_id: u32 = if (mat.metallic_roughness.base_color_texture) |tex_info| blk: {
            const texture = gltf.data.textures[tex_info.index];
            if (texture.source) |img_idx| break :blk bindless_slots[img_idx];
            break :blk 0;
        } else 0;

        const metal_rough_tex_id: u32 = if (mat.metallic_roughness.metallic_roughness_texture) |tex_info| blk: {
            const texture = gltf.data.textures[tex_info.index];
            if (texture.source) |img_idx| break :blk bindless_slots[img_idx];
            break :blk 0;
        } else 0;

        if (Config.log.mesh) {
            log.info("[DBG] mat[{d}] '{s}' color_tex_id={d} metal_rough_tex_id={d} colorFactors={d:.2},{d:.2},{d:.2},{d:.2}", .{
                i,                                           name,                                        color_tex_id,                                metal_rough_tex_id,
                mat.metallic_roughness.base_color_factor[0], mat.metallic_roughness.base_color_factor[1], mat.metallic_roughness.base_color_factor[2], mat.metallic_roughness.base_color_factor[3],
            });
        }

        scene_material_constants[i] = .{
            .color_factors = mat.metallic_roughness.base_color_factor,
            .metal_rough_factors = .{ mat.metallic_roughness.metallic_factor, mat.metallic_roughness.roughness_factor, 0, 0 },
            .color_tex_id = color_tex_id,
            .metal_rough_tex_id = metal_rough_tex_id,
        };

        new_mat.data = try engine.metal_rough_material.writeMaterial(engine, pass_type, material_resources, &loaded_gltf.descriptor_pool);

        self.materials.appendAssumeCapacity(new_mat);
        const new_mat_ptr = &self.materials.items[self.materials.items.len - 1];
        try loaded_gltf.materials.put(self.allocator, name, new_mat_ptr);
    }

    try loaded_gltf.material_data_buffer.copyInto(engine.ctx, std.mem.sliceAsBytes(scene_material_constants), 0);

    var indices = std.ArrayList(u32).empty;
    defer indices.deinit(self.allocator);
    var vertices = std.ArrayList(Vertex).empty;
    defer vertices.deinit(self.allocator);

    // Load Meshes
    for (gltf.data.meshes) |mesh| {
        const name = mesh.name orelse "";
        var mesh_asset = try Mesh.init(self.allocator);
        mesh_asset.name = name;

        indices.clearRetainingCapacity();
        vertices.clearRetainingCapacity();

        for (mesh.primitives) |primitive| {
            if (primitive.indices == null) {
                continue;
            }
            const primitive_index = primitive.indices.?;

            var new_surface: Mesh.GeoSurface = .{ .start_index = @intCast(indices.items.len), .count = @intCast(gltf.data.accessors[primitive_index].count) };

            if (primitive.material) |mat_idx| {
                new_surface.material = &self.materials.items[initial_material_index + mat_idx];
            } else {
                new_surface.material = &self.materials.items[initial_material_index];
            }

            const initial_vertex = vertices.items.len;

            { // load indexes
                const accessor = gltf.data.accessors[primitive_index];
                switch (accessor.component_type) {
                    .unsigned_integer => {
                        var it = accessor.iterator(u32, &gltf, glb_binary);

                        while (it.next()) |idxx| {
                            for (idxx) |v| {
                                try indices.append(self.allocator, @intCast(v + initial_vertex));
                            }
                        }
                    },
                    else => {
                        var it = accessor.iterator(u16, &gltf, glb_binary);

                        while (it.next()) |idxx| {
                            for (idxx) |v| {
                                try indices.append(self.allocator, @intCast(v + initial_vertex));
                            }
                        }
                    },
                }
            }

            { // load vertex
                for (primitive.attributes) |attribute| {
                    switch (attribute) {
                        .position => |idx| {
                            const accessor = gltf.data.accessors[idx];
                            var it = accessor.iterator(f32, &gltf, glb_binary);
                            while (it.next()) |v| {
                                try vertices.append(self.allocator, .{
                                    .pos = .{ v[0], v[1], v[2] },
                                    .normal = .{ 1, 0, 0 },
                                    .col = .{ 1.0, 1.0, 1.0, 1.0 },
                                    .uv_x = 0,
                                    .uv_y = 0,
                                });
                            }
                        },
                        .normal => |idx| {
                            const accessor = gltf.data.accessors[idx];
                            var it = accessor.iterator(f32, &gltf, glb_binary);
                            var i: u32 = 0;
                            while (it.next()) |v| : (i += 1) {
                                vertices.items[initial_vertex + i].normal = .{ v[0], v[1], v[2] };
                            }
                        },
                        .texcoord => |idx| {
                            const accessor = gltf.data.accessors[idx];
                            var it = accessor.iterator(f32, &gltf, glb_binary);
                            var i: u32 = 0;
                            while (it.next()) |uv| : (i += 1) {
                                vertices.items[initial_vertex + i].uv_x = uv[0];
                                vertices.items[initial_vertex + i].uv_y = uv[1];
                            }
                        },
                        .color => |idx| {
                            const accessor = gltf.data.accessors[idx];
                            var it = accessor.iterator(f32, &gltf, glb_binary);
                            var i: u32 = 0;
                            while (it.next()) |color| : (i += 1) {
                                vertices.items[initial_vertex + i].col = .{ color[0], color[1], color[2], color[3] };
                            }
                        },
                        else => {},
                    }
                }
            }

            { // Set Bounding cube/sphere
                var minpos: @Vector(3, f32) = vertices.items[initial_vertex].pos;
                var maxpos: @Vector(3, f32) = vertices.items[initial_vertex].pos;

                for (vertices.items[initial_vertex..]) |vtx| {
                    minpos = .{
                        @min(minpos[0], vtx.pos[0]),
                        @min(minpos[1], vtx.pos[1]),
                        @min(minpos[2], vtx.pos[2]),
                    };
                    maxpos = .{
                        @max(maxpos[0], vtx.pos[0]),
                        @max(maxpos[1], vtx.pos[1]),
                        @max(maxpos[2], vtx.pos[2]),
                    };
                }

                const origin: [3]f32 = ((maxpos + minpos) / @as(@Vector(3, f32), @splat(2.0)));
                const extents: [3]f32 = ((maxpos - minpos) / @as(@Vector(3, f32), @splat(2.0)));

                new_surface.bounds = .{
                    .origin = origin,
                    .extents = extents,
                    .sphere_radius = zm.length3(.{ extents[0], extents[1], extents[2], 0 })[0],
                };
            }

            try mesh_asset.surfaces.append(self.allocator, new_surface);
        }
        const owned_vertices = try vertices.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_vertices);
        const owned_indices = try indices.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_indices);

        try mesh_asset.uploadMesh(engine, owned_vertices, owned_indices);
        self.meshes.appendAssumeCapacity(mesh_asset);

        const mesh_ptr = &self.meshes.items[self.meshes.items.len - 1];
        try loaded_gltf.meshes.put(self.allocator, name, mesh_ptr);
    }

    // Load Nodes
    for (gltf.data.nodes, 0..) |node, i| {
        const name = node.name orelse "";
        var local_transform: zm.Mat = zm.identity();

        if (node.matrix) |matrix| {
            inline for (0..4) |row| {
                inline for (0..4) |col| {
                    local_transform[row][col] = matrix[row * 4 + col];
                }
            }
        } else {
            const transform: zm.Vec = .{ node.translation[0], node.translation[1], node.translation[2], 1 };
            const rotation: zm.Quat = .{ node.rotation[0], node.rotation[1], node.rotation[2], node.rotation[3] };
            const scale: zm.Vec = blk: {
                const s = node.scale;
                if (s[0] == 0 and s[1] == 0 and s[2] == 0) break :blk .{ 1, 1, 1, 0 };
                break :blk .{ s[0], s[1], s[2], 0 };
            };

            const tm = zm.translationV(transform);
            const rm = zm.quatToMat(rotation);
            const sm = zm.scalingV(scale);
            const sr = zm.mul(sm, rm);
            local_transform = zm.mul(sr, tm);
        }

        if (node.mesh) |mesh_idx| {
            const mesh_node = try self.arena.allocator().create(MeshNode);
            mesh_node.* = try MeshNode.init(self.allocator);
            mesh_node.mesh = &self.meshes.items[initial_mesh_index + mesh_idx];

            mesh_node.local_transform = local_transform;
            self.nodes.appendAssumeCapacity(mesh_node.interface());
        } else {
            const new_node = try self.arena.allocator().create(BasicNode);
            new_node.* = try BasicNode.init(self.allocator);
            new_node.local_transform = local_transform;
            self.nodes.appendAssumeCapacity(new_node.interface());
        }

        try loaded_gltf.nodes.put(self.allocator, name, &self.nodes.items[initial_node_index + i]);
    }

    // Create Node hierarchy
    for (gltf.data.nodes, 0..) |node, i| {
        var scene_node = &self.nodes.items[initial_node_index + i];

        for (node.children) |j| {
            var child_ptr = &self.nodes.items[initial_node_index + j];
            try scene_node.children().append(self.allocator, child_ptr);
            child_ptr.setParent(scene_node);
        }
    }

    // Find the top Nodes with no parents
    for (self.nodes.items[initial_node_index..]) |*node| {
        if (node.getParent() == null) {
            try loaded_gltf.top_nodes.append(self.allocator, node);
            node.refreshTransform(zm.identity());
        }
    }

    return loaded_gltf;
}

fn extractFilter(filter: Gltf.MagFilter) Sampler.SamplerType {
    return switch (filter) {
        .linear => .linear,
        .nearest => .nearest,
    };
}

fn extractMipmapMode(filter: Gltf.MinFilter) Sampler.SamplerType {
    return switch (filter) {
        .linear, .linear_mipmap_linear, .nearest_mipmap_linear => .linear,
        .nearest, .nearest_mipmap_nearest, .linear_mipmap_nearest => .nearest,
    };
}
