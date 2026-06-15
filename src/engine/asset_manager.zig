const std = @import("std");
const log = std.log.scoped(.asset_loader);
const assert = std.debug.assert;
const zm = @import("zmath");
const Gltf = @import("zgltf").Gltf;

const Engine = @import("vulkan/engine.zig");
const Sampler = @import("vulkan/sampler.zig");
const PoolSizeRatio = @import("vulkan/descriptor.zig").DescriptorAllocator.PoolSizeRatio;
const Mesh = @import("vulkan/mesh.zig");
const Image = @import("vulkan/image.zig");
const Buffer = @import("vulkan/buffer.zig");
const MetallicRoughness = @import("graphics/materials.zig").MetallicRoughness;
const MaterialPass = @import("graphics/materials.zig").MaterialPass;

const Scene = @import("graphics/scene.zig");
const LoadedGLTF = Scene.LoadedGLTF;
const BasicNode = Scene.BasicNode;
const MeshNode = Scene.MeshNode;
const IRenderable = Scene.IRenderable;
const Vertex = @import("graphics/buffers.zig").Vertex;

const AssetManager = @This();

const MAX_FILE_SIZE = 512_000_000_000;

io: std.Io,
allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
zgltf: Gltf,

meshes: std.ArrayList(Mesh),
nodes: std.ArrayList(IRenderable),
materials: std.ArrayList(Mesh.GLTFMaterial),

pub fn init(allocator: std.mem.Allocator, io: std.Io) !AssetManager {
    return .{
        .io = io,
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .zgltf = Gltf.init(allocator),
        .materials = try .initCapacity(allocator, 0),
        .meshes = try .initCapacity(allocator, 0),
        .nodes = try .initCapacity(allocator, 0),
    };
}

pub fn deinit(self: *AssetManager, engine: *const Engine) void {
    self.zgltf.deinit();
    for (self.meshes.items) |*mesh| {
        mesh.destroy(engine.ctx);
    }
    self.meshes.deinit(self.allocator);

    self.nodes.deinit(self.allocator);
    self.materials.deinit(self.allocator);
}

pub fn loadGLTFAsset(self: *AssetManager, engine: *Engine, filename: []const u8) !LoadedGLTF {
    const extension = std.fs.path.extension(filename);
    var data: Gltf.Data = undefined;

    if (std.mem.eql(u8, extension, ".glb") or std.mem.eql(u8, extension, ".gltf")) {
        const cwd = std.Io.Dir.cwd();
        const buffer = try cwd.readFileAllocOptions(self.io, filename, self.allocator, std.Io.Limit.limited(MAX_FILE_SIZE), .@"4", null);
        try self.zgltf.parse(buffer);
        data = self.zgltf.data;
    } else {
        return error.FileNotSupported;
    }

    var loaded_gltf: LoadedGLTF = try LoadedGLTF.init(self.allocator);
    loaded_gltf.creator = engine;

    const initial_mesh_index = self.meshes.items.len;
    const initial_node_index = self.nodes.items.len;
    const initial_material_index = self.materials.items.len;
    try self.meshes.ensureTotalCapacity(self.allocator, initial_mesh_index + data.meshes.len);
    try self.nodes.ensureTotalCapacity(self.allocator, initial_node_index + data.nodes.len);
    try self.materials.ensureTotalCapacity(self.allocator, initial_material_index + data.materials.len);

    const pool_ratios: [3]PoolSizeRatio = .{
        .{ .vk_type = .combined_image_sampler, .ratio = 3 },
        .{ .vk_type = .uniform_buffer, .ratio = 3 },
        .{ .vk_type = .storage_buffer, .ratio = 1 },
    };
    loaded_gltf.descriptor_pool = try .init(self.allocator, engine.ctx, @intCast(data.materials.len), &pool_ratios);

    // Load Samplers
    for (data.samplers) |*samp| {
        const mag_filter = extractFilter(samp.mag_filter orelse .nearest);
        const mipmap_mode = extractMipmapMode(samp.min_filter orelse .nearest);

        const sampler_option: Sampler.SamplerOption = .{
            .min_filter = mipmap_mode,
            .mag_filter = mag_filter,
            .mipmap_mode = mipmap_mode,
            .max_lod = 0,
            .min_lod = 0,
        };

        const sampler = try Sampler.create(engine.ctx, sampler_option);
        try loaded_gltf.samplers.append(self.allocator, sampler);
    }

    var images = try std.ArrayList(*Image).initCapacity(self.allocator, data.images.len);

    // Load Textures
    for (data.images) |*img| {
        const name = img.name orelse "";

        if (img.uri) |uri| {
            var image = try Image.createFromPath(engine, uri, .packed_rgba_8_8_8_8, .{ .sampled_bit = true }, .{});
            try loaded_gltf.images.put(self.allocator, name, image);
            images.appendAssumeCapacity(&image);
        } else if (img.data) |bytes| {
            var image = try Image.createFromImageBytes(engine, bytes, .{ .sampled_bit = true }, .{});
            try loaded_gltf.images.put(self.allocator, name, image);
            images.appendAssumeCapacity(&image);
        } else {
            log.warn("Missing image {s}", .{name});
            images.appendAssumeCapacity(engine.images.getPtr(.error_checker));
        }
    }

    loaded_gltf.material_data_buffer = try MetallicRoughness.createMaterialPushConstantsBuffer(engine, @intCast(data.materials.len));

    const scene_material_constants = try self.allocator.alloc(MetallicRoughness.MaterialConstants, data.materials.len);
    defer self.allocator.free(scene_material_constants);

    // Load Materials
    for (data.materials, 0..) |mat, i| {
        const name = mat.name orelse "";
        var new_mat: Mesh.GLTFMaterial = undefined;

        scene_material_constants[i] = .{
            .color_factors = mat.metallic_roughness.base_color_factor,
            .metal_rough_factors = @Vector(4, f32){ mat.metallic_roughness.metallic_factor, mat.metallic_roughness.roughness_factor, 0, 0 },
            .extra = [_]@Vector(4, f32){@splat(0)} ** 14,
        };

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
            const texture = data.textures[tex_info.index];
            if (texture.source) |img_idx| {
                material_resources.color_image = images.items[img_idx].*;
            }

            if (texture.sampler) |sampler_idx| {
                material_resources.color_sampler = loaded_gltf.samplers.items[sampler_idx];
            }
        }

        new_mat.data = try engine.metal_rough_material.writeMaterial(engine, pass_type, material_resources, &loaded_gltf.descriptor_pool);

        try loaded_gltf.materials.put(self.allocator, name, &new_mat);
        self.materials.appendAssumeCapacity(new_mat);
    }

    try loaded_gltf.material_data_buffer.copyInto(engine.ctx, std.mem.sliceAsBytes(scene_material_constants), 0);

    var indices = try std.ArrayList(u32).initCapacity(self.allocator, 0);
    defer indices.deinit(self.allocator);
    var vertices = try std.ArrayList(Vertex).initCapacity(self.allocator, 0);
    defer vertices.deinit(self.allocator);

    // Load Meshes
    for (data.meshes) |mesh| {
        const name = mesh.name orelse "";
        var mesh_asset = try Mesh.init(self.allocator);

        indices.clearRetainingCapacity();
        vertices.clearRetainingCapacity();

        for (mesh.primitives) |primitive| {
            if (primitive.indices == null) {
                continue;
            }
            const primitive_index = primitive.indices.?;

            var new_surface: Mesh.GeoSurface = .{ .start_index = @intCast(indices.items.len), .count = @intCast(data.accessors[primitive_index].count) };

            if (primitive.material) |mat_idx| {
                new_surface.material = &self.materials.items[initial_material_index + mat_idx];
            } else {
                new_surface.material = &self.materials.items[initial_material_index];
            }

            try mesh_asset.surfaces.append(self.allocator, new_surface);

            const initial_vertex = vertices.items.len;

            { // load indexes
                if (self.zgltf.glb_binary) |bin| {
                    const accessor = data.accessors[primitive_index];
                    switch (accessor.component_type) {
                        .unsigned_integer => {
                            var it = accessor.iterator(u32, &self.zgltf, bin);

                            while (it.next()) |idxx| {
                                try indices.appendSlice(self.allocator, idxx);
                            }
                        },
                        else => {
                            var it = accessor.iterator(u16, &self.zgltf, bin);

                            while (it.next()) |idxx| {
                                for (idxx) |v| try indices.append(self.allocator, @intCast(v));
                            }
                        },
                    }
                }
            }

            { // load vertex
                if (self.zgltf.glb_binary) |bin| {
                    for (primitive.attributes) |attribute| {
                        switch (attribute) {
                            .position => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
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
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |v| : (i += 1) {
                                    vertices.items[initial_vertex + i].normal = .{ v[0], v[1], v[2] };
                                }
                            },
                            .texcoord => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |uv| : (i += 1) {
                                    vertices.items[initial_vertex + i].uv_x = uv[0];
                                    vertices.items[initial_vertex + i].uv_y = uv[1];
                                }
                            },
                            .color => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |color| : (i += 1) {
                                    vertices.items[initial_vertex + i].col = .{ color[0], color[1], color[2], color[3] };
                                }
                            },
                            else => {},
                        }
                    }
                }
            }
        }
        try mesh_asset.uploadMesh(engine, try vertices.toOwnedSlice(self.allocator), try indices.toOwnedSlice(self.allocator));
        mesh_asset.name = name;
        try loaded_gltf.meshes.put(self.allocator, name, &mesh_asset);
        self.meshes.appendAssumeCapacity(mesh_asset);
    }

    // Load Nodes
    for (data.nodes, 0..) |node, i| {
        const name = node.name orelse "";
        var local_transform: zm.Mat = zm.identity();

        if (node.matrix) |matrix| {
            inline for (0..4) |row| {
                inline for (0..4) |col| {
                    local_transform[row][col] = matrix[row * 4 + col];
                }
            }
        } else {
            const transform: zm.Vec = .{ node.translation[0], node.translation[1], node.translation[2], 0 };
            const rotation: zm.Quat = .{ node.rotation[3], node.rotation[0], node.rotation[1], node.rotation[2] };
            const scale: zm.Vec = .{ node.scale[0], node.scale[1], node.scale[2], 0 };

            const tm = zm.translationV(transform);
            const rm = zm.quatToMat(rotation);
            const sm = zm.scalingV(scale);
            const tr = zm.mul(tm, rm);
            const trs = zm.mul(tr, sm);

            local_transform = trs;
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
    for (data.nodes, 0..) |node, i| {
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

fn load(self: *AssetManager, filename: []const u8) !Gltf.Data {
    log.info("Parse file: {s}", .{filename});

    const cwd = std.Io.Dir.cwd();
    const buffer = try cwd.readFileAllocOptions(self.io, filename, self.allocator, std.Io.Limit.limited(MAX_FILE_SIZE), .@"4", null);
    try self.zgltf.parse(buffer);

    return self.zgltf.data;
}

pub fn loadMeshes(self: *AssetManager, engine: *Engine, filename: []const u8) !std.ArrayList(Mesh) {
    const extension = std.fs.path.extension(filename);
    var data: Gltf.Data = undefined;

    if (std.mem.eql(u8, extension, ".glb")) {
        data = try self.load(filename);
    } else {
        data = try self.load(filename);
    }

    var meshes = try std.ArrayList(Mesh).initCapacity(self.allocator, data.meshes.len);
    var indices = try std.ArrayList(u32).initCapacity(self.allocator, 0);
    defer indices.deinit(self.allocator);
    var vertices = try std.ArrayList(Vertex).initCapacity(self.allocator, 0);
    defer vertices.deinit(self.allocator);

    for (data.meshes) |m| {
        var mesh: Mesh = try .init(self.allocator);
        if (m.name) |name| {
            mesh.name = name;
        }

        indices.clearRetainingCapacity();
        vertices.clearRetainingCapacity();

        for (m.primitives) |primitive| {
            if (primitive.indices == null) {
                continue;
            }
            const primitive_index = primitive.indices.?;
            const surface: Mesh.GeoSurface = .{ .start_index = @intCast(indices.items.len), .count = @intCast(data.accessors[primitive_index].count) };
            try mesh.surfaces.append(self.allocator, surface);

            const initial_vertex = vertices.items.len;

            { // load indexes
                if (self.zgltf.glb_binary) |bin| {
                    const accessor = data.accessors[primitive_index];
                    switch (accessor.component_type) {
                        .unsigned_integer => {
                            var it = accessor.iterator(u32, &self.zgltf, bin);

                            // Append only — don't resize+append (would double the buffer
                            // with garbage front-padding and shift the real indices).
                            while (it.next()) |idxx| {
                                try indices.appendSlice(self.allocator, idxx);
                            }
                        },
                        else => {
                            var it = accessor.iterator(u16, &self.zgltf, bin);

                            // Append only — don't resize+append (would double the buffer
                            // with garbage front-padding and shift the real indices).
                            while (it.next()) |idxx| {
                                for (idxx) |v| try indices.append(self.allocator, @intCast(v));
                            }
                        },
                    }
                }
            }

            { // load vertex
                if (self.zgltf.glb_binary) |bin| {
                    // ================== DEBUG ===============
                    std.debug.print("  [SELFTEST] primitive.attributes (in order, with tag and accessor idx):\n", .{});
                    for (primitive.attributes) |attribute| {
                        const idx_and_label: struct { idx: usize, label: []const u8 } = switch (attribute) {
                            .position => |i| .{ .idx = i, .label = ".position" },
                            .normal => |i| .{ .idx = i, .label = ".normal  " },
                            .texcoord => |i| .{ .idx = i, .label = ".texcoord" },
                            .color => |i| .{ .idx = i, .label = ".color   " },
                            else => continue,
                        };
                        const acc = data.accessors[idx_and_label.idx];
                        const bv_idx = acc.buffer_view.?;
                        const bv = data.buffer_views[bv_idx];
                        std.debug.print("    {s} → accessor[{d}] (type={s}, comp={s}, count={d}, acc.byte_offset={d}) → buffer_view[{d}] (bv.byte_offset={d}, bv.byte_length={d}, bv.byte_stride={?})\n", .{
                            idx_and_label.label, idx_and_label.idx, @tagName(acc.type), @tagName(acc.component_type), acc.count, acc.byte_offset,
                            bv_idx,              bv.byte_offset,    bv.byte_length,     bv.byte_stride,
                        });
                    }
                    // ==================================
                    for (primitive.attributes) |attribute| {
                        switch (attribute) {
                            .position => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                while (it.next()) |v| {
                                    try vertices.append(self.allocator, .{
                                        .pos = .{ v[0], v[1], v[2] },
                                        .normal = .{ 0, 0, 1 },
                                        .col = .{ 1.0, 1.0, 1.0, 1.0 },
                                        .uv_x = 0,
                                        .uv_y = 0,
                                    });
                                }
                            },
                            .normal => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |v| : (i += 1) {
                                    vertices.items[initial_vertex + i].normal = .{ v[0], v[1], v[2] };
                                }
                            },
                            .texcoord => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |uv| : (i += 1) {
                                    vertices.items[initial_vertex + i].uv_x = uv[0];
                                    vertices.items[initial_vertex + i].uv_y = uv[1];
                                }
                            },
                            .color => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |color| : (i += 1) {
                                    vertices.items[initial_vertex + i].col = .{ color[0], color[1], color[2], color[3] };
                                }
                            },
                            else => {},
                        }
                    }
                }
            }
        }

        try mesh.uploadMesh(engine, try vertices.toOwnedSlice(self.allocator), try indices.toOwnedSlice(self.allocator));

        meshes.appendAssumeCapacity(mesh);
    }

    return meshes;
}
