const std = @import("std");
const log = std.log.scoped(.asset_manager);
const zm = @import("zmath");
const Uuid = @import("uuid");
const Gltf = @import("zgltf").Gltf;

const AssetManager = @This();
const Config = @import("../../config.zig");

const Engine = @import("../../engine/vulkan/engine.zig");
const Scene = @import("../../engine/graphics/scene.zig");
const LoadedGLTF = Scene.LoadedGLTF;
const BasicNode = Scene.BasicNode;
const MeshNode = Scene.MeshNode;
const IRenderable = Scene.IRenderable;
const Sampler = @import("../../engine/vulkan/sampler.zig");
const Mesh = @import("../../engine/vulkan/mesh.zig");
const Image = @import("../../engine/vulkan/image.zig");
const Buffer = @import("../../engine/vulkan/buffer.zig");
const MetallicRoughness = @import("../../engine/graphics/materials.zig").MetallicRoughness;
const MaterialPass = @import("../../engine/graphics/materials.zig").MaterialPass;
const MaterialResources = @import("../../engine/graphics/materials.zig").MetallicRoughness.MaterialResources;
const Vertex = @import("../../engine/graphics/buffers.zig").Vertex;

allocator: std.mem.Allocator,
io: std.Io,
pool: AssetPool,

pub const AssetPool = struct {
    pub const MAX_FILE_SIZE = 512_000_000_000;

    loaded_gltf: std.array_hash_map.String(LoadedGLTF),
    meshes: std.ArrayList(Mesh),
    nodes: std.ArrayList(IRenderable),
    materials: std.ArrayList(Mesh.GLTFMaterial),
    images: std.ArrayList(Image),
    arena: std.heap.ArenaAllocator,

    _current_img_idx: usize = 0,

    pub fn init(allocator: std.mem.Allocator) AssetPool {
        return .{
            .loaded_gltf = .empty,
            .materials = .empty,
            .meshes = .empty,
            .nodes = .empty,
            .images = .empty,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *AssetPool, allocator: std.mem.Allocator, engine: *Engine) void {
        var it = self.loaded_gltf.iterator();
        while (it.next()) |scene_ptr| {
            scene_ptr.value_ptr.*.deinit();
        }
        self.loaded_gltf.deinit(allocator);

        for (self.meshes.items) |*mesh| {
            mesh.destroy(engine.ctx);
        }
        self.meshes.deinit(allocator);

        self.nodes.deinit(allocator);
        self.materials.deinit(allocator);

        for (self.images.items) |*img| {
            // Don't destroy the error_checker image because it is owned by the engine
            if (engine.images.get(.error_checker).vk_image == img.vk_image) {
                continue;
            }

            img.destroy(engine.ctx);
        }

        self.images.deinit(allocator);
    }
};

pub fn init(allocator: std.mem.Allocator, io: std.Io) AssetManager {
    return .{
        .allocator = allocator,
        .io = io,
        .pool = .init(allocator),
    };
}

pub fn deinit(self: *AssetManager, engine: *Engine) void {
    self.pool.deinit(self.allocator, engine);
}

pub fn saveAssetPool(self: *AssetManager, project_path: []const u8) !void {
    _ = self;
    _ = project_path;
}

pub fn load(self: *AssetManager, engine: *Engine, asset_path: []const u8) !void {
    const structure_file = try self.loadGLTFAsset(engine, asset_path);
    const name = std.fs.path.stem(asset_path);
    try self.pool.loaded_gltf.put(self.allocator, name, structure_file);
}

// TODO, decouple engine such as the asset is loaded in the pool then have a function to load the pool in the GPU
pub fn loadGLTFAsset(self: *AssetManager, engine: *Engine, file_path: []const u8) !void {
    var gltf = Gltf.init(self.allocator);
    defer gltf.deinit();

    const extension = std.fs.path.extension(file_path);
    const filename = std.fs.path.stem(file_path);

    if (std.mem.eql(u8, extension, ".glb") or std.mem.eql(u8, extension, ".gltf")) {
        const cwd = std.Io.Dir.cwd();
        const buffer = try cwd.readFileAllocOptions(self.io, file_path, self.allocator, std.Io.Limit.limited(AssetPool.MAX_FILE_SIZE), .@"4", null);
        try gltf.parse(buffer);
    } else {
        return error.FileNotSupported;
    }

    if (null == gltf.glb_binary) return error.GlbBinaryEmpty;
    const glb_binary = gltf.glb_binary.?;

    var loaded_gltf: LoadedGLTF = try LoadedGLTF.init(self.allocator);
    loaded_gltf.creator = engine;

    const initial_mesh_index = self.pool.meshes.items.len;
    const initial_node_index = self.pool.nodes.items.len;
    const initial_material_index = self.pool.materials.items.len;
    try self.pool.meshes.ensureTotalCapacity(self.allocator, initial_mesh_index + gltf.data.meshes.len);
    try self.pool.nodes.ensureTotalCapacity(self.allocator, initial_node_index + gltf.data.nodes.len);
    try self.pool.materials.ensureTotalCapacity(self.allocator, initial_material_index + gltf.data.materials.len);

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
            .address_mode_u = switch (samp.wrap_s) {
                .clamp_to_edge => .clamp_to_edge,
                .repeat => .repeat,
                .mirrored_repeat => .mirrored_repeat,
            },
            .address_mode_v = switch (samp.wrap_t) {
                .clamp_to_edge => .clamp_to_edge,
                .repeat => .repeat,
                .mirrored_repeat => .mirrored_repeat,
            },
        };

        const sampler = try Sampler.create(engine.ctx, sampler_option);
        try loaded_gltf.samplers.append(self.allocator, sampler);
    }

    self.pool._current_img_idx = self.pool.images.items.len;
    try self.pool.images.ensureTotalCapacity(self.allocator, self.pool._current_img_idx + gltf.data.images.len);

    const bindless_slots = try self.allocator.alloc(u32, gltf.data.textures.len);
    defer self.allocator.free(bindless_slots);

    if (Config.log.mesh) {
        log.info("[DBG] GLTF images: {d}, materials: {d}, textures: {d}", .{ gltf.data.images.len, gltf.data.materials.len, gltf.data.textures.len });
    }

    var alpha_matter_image_idx: std.hash_map.AutoHashMap(u32, bool) = .init(self.allocator);
    defer alpha_matter_image_idx.deinit();
    // Cache images that require the alpha value (emissive image and base color)
    for (gltf.data.materials) |mat| {
        if (mat.emissive_texture) |t| {
            try alpha_matter_image_idx.put(@intCast(t.index), true);
        }
        if (mat.metallic_roughness.base_color_texture) |t| {
            try alpha_matter_image_idx.put(@intCast(t.index), true);
        }
    }

    // Load Textures
    for (gltf.data.images, 0..) |*img, i| {
        const name = img.name orelse blk: {
            const alt_name = std.fmt.allocPrint(self.allocator, "unamed_idx_{}", .{i}) catch "";

            break :blk alt_name;
        };

        const image = if (img.uri) |uri| blk: {
            if (Config.log.mesh) {
                log.info("[DBG] image[{d}] uri={s}", .{ i, uri });
            }
            break :blk Image.createFromPath(engine, uri, .packed_rgba_8_8_8_8, .{ .sampled_bit = true }) catch engine.images.get(.error_checker);
        } else if (img.data) |bytes| blk: {
            if (Config.log.mesh) {
                log.info("[DBG] image[{d}] embedded {d} bytes mime={?s}", .{ i, bytes.len, img.mime_type });
            }
            const is_alpha_matter = (alpha_matter_image_idx.get(@intCast(i)) != null);
            break :blk Image.createFromBytesWithSDL(engine, bytes, img.mime_type, .{ .sampled_bit = true }, is_alpha_matter) catch engine.images.get(.error_checker);
        } else blk: {
            if (Config.log.mesh) {
                log.warn("[DBG] image[{d}] MISSING — using error_checker", .{i});
            }
            break :blk engine.images.get(.error_checker);
        };

        self.pool.images.appendAssumeCapacity(image);
        if (Config.log.mesh) {
            log.info("[DBG] image[{d}] '{s}' → bindless slot {d}", .{ i, name, bindless_slots[i] });
        }
        try loaded_gltf.images.put(self.allocator, name, &self.pool.images.items[self.pool._current_img_idx + i]);
    }

    loaded_gltf.material_data_buffer = try MetallicRoughness.createMaterialPushConstantsBuffer(engine, @intCast(gltf.data.materials.len));

    for (gltf.data.textures, 0..) |tex, i| {
        if (tex.source != null and tex.sampler != null) {
            bindless_slots[i] = try engine.registerTexture(self.pool.images.items[self.pool._current_img_idx + tex.source.?], loaded_gltf.samplers.items[tex.sampler.?]);
        }
        if (tex.source != null and tex.sampler == null) {
            log.warn("GLTF is missing a sampler, using default engine linear sampler. Texture ID: {}", .{i});
            bindless_slots[i] = try engine.registerTexture(self.pool.images.items[self.pool._current_img_idx + tex.source.?], engine.samplers.get(.linear));
        }
    }

    const scene_material_constants = try self.allocator.alloc(MetallicRoughness.MaterialConstants, gltf.data.materials.len);
    defer self.allocator.free(scene_material_constants);

    // Load Materials
    {
        for (gltf.data.materials, 0..) |mat, i| {
            const name = mat.name orelse blk: {
                const alt_name = std.fmt.allocPrint(self.allocator, "unamed_idx_{}", .{i}) catch "";

                break :blk alt_name;
            };
            var new_mat: Mesh.GLTFMaterial = undefined;

            const pass_type: MaterialPass = if (mat.alpha_mode == .blend) .Transparent else .MainColor;

            var material_resources: MetallicRoughness.MaterialResources = .{
                .color_image = engine.images.get(.white),
                .color_sampler = engine.samplers.get(.linear),
                .metal_rough_image = engine.images.get(.white),
                .metal_rough_sampler = engine.samplers.get(.linear),
                .normal_image = engine.images.get(.white),
                .normal_sampler = engine.samplers.get(.linear),
                .emissive_image = engine.images.get(.white),
                .emissive_sampler = engine.samplers.get(.linear),
                .occlusion_image = engine.images.get(.white),
                .occlusion_sampler = engine.samplers.get(.linear),
                .transmission_image = engine.images.get(.white),
                .transmission_sampler = engine.samplers.get(.linear),
                .data_buffer = loaded_gltf.material_data_buffer,
                .data_buffer_offset = i * @sizeOf(MetallicRoughness.MaterialConstants),
            };

            const color_tex_id = self.parseTexture(gltf.data, mat.metallic_roughness.base_color_texture, &loaded_gltf, &material_resources, bindless_slots, "color_image", "color_sampler");
            const metal_rough_tex_id = self.parseTexture(gltf.data, mat.metallic_roughness.metallic_roughness_texture, &loaded_gltf, &material_resources, bindless_slots, "metal_rough_image", "metal_rough_sampler");
            const normal_tex_id = self.parseTexture(gltf.data, mat.normal_texture, &loaded_gltf, &material_resources, bindless_slots, "normal_image", "normal_sampler");
            const occlusion_tex_id = self.parseTexture(gltf.data, mat.occlusion_texture, &loaded_gltf, &material_resources, bindless_slots, "occlusion_image", "occlusion_sampler");
            const emissive_tex_id = self.parseTexture(gltf.data, mat.emissive_texture, &loaded_gltf, &material_resources, bindless_slots, "emissive_image", "emissive_sampler");
            const transmission_tex_id = self.parseTexture(gltf.data, mat.transmission_texture, &loaded_gltf, &material_resources, bindless_slots, "transmission_image", "transmission_sampler");

            if (Config.log.mesh) {
                log.info("[DBG] mat[{d}] '{s}' color={d} metalRough={d} normal={d} occlusion={d} emissive={d} transmission={d} transmissionFactor={d:.2} colorFactors={d:.2},{d:.2},{d:.2},{d:.2}", .{
                    i,                                           name,                                        color_tex_id,
                    metal_rough_tex_id,                          normal_tex_id,                               occlusion_tex_id,
                    emissive_tex_id,                             transmission_tex_id,                         mat.transmission_factor,
                    mat.metallic_roughness.base_color_factor[0], mat.metallic_roughness.base_color_factor[1], mat.metallic_roughness.base_color_factor[2],
                    mat.metallic_roughness.base_color_factor[3],
                });
            }

            scene_material_constants[i] = .{
                .color_factors = mat.metallic_roughness.base_color_factor,
                .metal_rough_factors = .{ mat.metallic_roughness.metallic_factor, mat.metallic_roughness.roughness_factor, 0, 0 },
                .transmission_factor = mat.transmission_factor,
                .color_tex_id = color_tex_id,
                .metal_rough_tex_id = metal_rough_tex_id,
                .normal_tex_id = normal_tex_id,
                .occlusion_tex_id = occlusion_tex_id,
                .emissive_tex_id = emissive_tex_id,
                .emissive_factor = .{ mat.emissive_factor[0], mat.emissive_factor[1], mat.emissive_factor[2], mat.emissive_strength },
                .transmission_tex_id = transmission_tex_id,
            };

            new_mat.data = try engine.metal_rough_material.writeMaterial(engine, pass_type, material_resources, &loaded_gltf.descriptor_pool);

            self.pool.materials.appendAssumeCapacity(new_mat);
            const new_mat_ptr = &self.pool.materials.items[self.pool.materials.items.len - 1];
            try loaded_gltf.materials.put(self.allocator, name, new_mat_ptr);
        }

        try loaded_gltf.material_data_buffer.copyInto(engine.ctx, std.mem.sliceAsBytes(scene_material_constants), 0);
    }

    var indices = std.ArrayList(u32).empty;
    defer indices.deinit(self.allocator);
    var vertices = std.ArrayList(Vertex).empty;
    defer vertices.deinit(self.allocator);

    // Load Meshes
    for (gltf.data.meshes, 0..) |mesh, j| {
        const name = mesh.name orelse blk: {
            const alt_name = std.fmt.allocPrint(self.allocator, "unamed_idx_{}", .{j}) catch "";

            break :blk alt_name;
        };
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
                new_surface.material = &self.pool.materials.items[initial_material_index + mat_idx];
            } else {
                new_surface.material = &self.pool.materials.items[initial_material_index];
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
                                    .tangent = .{ 0, 1, 0 },
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
                        .tangent => |idx| {
                            const accessor = gltf.data.accessors[idx];
                            var it = accessor.iterator(f32, &gltf, glb_binary);
                            var i: u32 = 0;
                            while (it.next()) |t| : (i += 1) {
                                vertices.items[initial_vertex + i].tangent = .{ t[0], t[1], t[2] };
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
        self.pool.meshes.appendAssumeCapacity(mesh_asset);

        const mesh_ptr = &self.pool.meshes.items[self.pool.meshes.items.len - 1];
        try loaded_gltf.meshes.put(self.allocator, name, mesh_ptr);
    }

    // Load Nodes
    for (gltf.data.nodes, 0..) |node, i| {
        const name = node.name orelse blk: {
            const alt_name = std.fmt.allocPrint(self.allocator, "unamed_idx_{}", .{i}) catch "";

            break :blk alt_name;
        };
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
            const mesh_node = try self.pool.arena.allocator().create(MeshNode);
            mesh_node.* = try MeshNode.init(self.allocator);
            mesh_node.mesh = &self.pool.meshes.items[initial_mesh_index + mesh_idx];

            mesh_node.local_transform = local_transform;
            self.pool.nodes.appendAssumeCapacity(mesh_node.interface());
        } else {
            const new_node = try self.pool.arena.allocator().create(BasicNode);
            new_node.* = try BasicNode.init(self.allocator);
            new_node.local_transform = local_transform;
            self.pool.nodes.appendAssumeCapacity(new_node.interface());
        }

        try loaded_gltf.nodes.put(self.allocator, name, &self.pool.nodes.items[initial_node_index + i]);
    }

    // Create Node hierarchy
    for (gltf.data.nodes, 0..) |node, i| {
        var scene_node = &self.pool.nodes.items[initial_node_index + i];

        for (node.children) |j| {
            var child_ptr = &self.pool.nodes.items[initial_node_index + j];
            try scene_node.children().append(self.allocator, child_ptr);
            child_ptr.setParent(scene_node);
        }
    }

    // Find the top Nodes with no parents
    for (self.pool.nodes.items[initial_node_index..]) |*node| {
        if (node.getParent() == null) {
            try loaded_gltf.top_nodes.append(self.allocator, node);
            node.refreshTransform(zm.identity());
        }
    }

    if (self.pool.loaded_gltf.fetchSwapRemove(filename)) |removed| {
        log.warn("Reloading GLTF asset '{s}': destroying previous instance to avoid leaking GPU resources", .{filename});
        var old_gltf = removed.value;
        old_gltf.deinit();
    }

    try self.pool.loaded_gltf.put(self.allocator, filename, loaded_gltf);
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

/// Resolves a glTF texture reference (base color / metallic-roughness / normal /
/// occlusion / emissive — anything shaped like `?{ index, texcoord, ... }`) into
/// bindless data: writes the resolved `Image`/`Sampler` into the named fields of
/// `material_resources` (via comptime field-name reflection, since each texture
/// kind targets a different pair of fields on the same struct) and returns the
/// bindless slot id for the material's UBO. Returns `0` when the texture is absent
/// or has no source image, matching the pre-refactor fallback behavior.
fn parseTexture(
    self: *AssetManager,
    gltf_data: Gltf.Data,
    tex_info: anytype,
    loaded_gltf: *LoadedGLTF,
    material_resources: *MaterialResources,
    bindless_slots: []const u32,
    comptime image_field: []const u8,
    comptime sampler_field: []const u8,
) u32 {
    const info = tex_info orelse return 0;
    const texture = gltf_data.textures[info.index];

    if (texture.sampler) |sampler_idx| {
        @field(material_resources.*, sampler_field) = loaded_gltf.samplers.items[sampler_idx];
    }

    const img_idx = texture.source orelse return 0;
    @field(material_resources.*, image_field) = self.pool.images.items[self.pool._current_img_idx + img_idx];
    return bindless_slots[info.index];
}
