const std = @import("std");
const log = std.log.scoped(.asset_loader);
const assert = std.debug.assert;
const Gltf = @import("zgltf").Gltf;

const Mesh = @import("mesh.zig");
const Data = @import("../data.zig");
const CommandPool = @import("command_pool.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");

const AssetLoader = @This();

allocator: std.mem.Allocator,
zgltf: Gltf,

pub fn init(allocator: std.mem.Allocator) AssetLoader {
    return .{ .allocator = allocator, .zgltf = Gltf.init(allocator) };
}

pub fn deinit(self: *AssetLoader) void {
    self.zgltf.deinit();
}

pub fn loadGlb(self: *AssetLoader, glb_filename: []const u8) !Gltf.Data {
    assert(std.mem.eql(u8, std.fs.path.extension(glb_filename), ".glb"));
    log.info("Parse GLB file: {s}", .{glb_filename});

    const buffer = try std.fs.cwd().readFileAllocOptions(self.allocator, glb_filename, 512_000, null, .@"4", null);
    defer self.allocator.free(buffer);

    try self.zgltf.parse(buffer);
    self.zgltf.debugPrint();

    return self.zgltf.data;
}

pub fn loadGltf(self: *AssetLoader, gltf_filename: []const u8) !Gltf.Data {
    assert(std.mem.eql(u8, std.fs.path.extension(gltf_filename), ".gltf"));
    log.info("Parse GLTF file: {s}", .{gltf_filename});

    const buffer = try std.fs.cwd().readFileAllocOptions(self.allocator, gltf_filename, 512_000, null, .@"4", null);
    defer self.allocator.free(buffer);

    try self.zgltf.parse(buffer);
    self.zgltf.debugPrint();

    return self.zgltf.data;
}

pub fn loadMeshes(self: *AssetLoader, ctx: *const GraphicsContext, cmd_pool: *const CommandPool, filename: []const u8) !std.ArrayList(Mesh) {
    const extension = std.fs.path.extension(filename);
    var data: Gltf.Data = undefined;

    if (std.mem.eql(u8, extension, ".glb")) {
        data = try self.loadGlb(filename);
    } else {
        data = try self.loadGltf(filename);
    }

    var meshes = try std.ArrayList(Mesh).initCapacity(self.allocator, data.meshes.len);
    var indices = try std.ArrayList(Data.Indice).initCapacity(self.allocator, 0);
    defer indices.deinit(self.allocator);
    var vertices = try std.ArrayList(Data.Vertex).initCapacity(self.allocator, 0);
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
                    var it = accessor.iterator(Data.Indice, &self.zgltf, bin);
                    try indices.resize(self.allocator, indices.items.len + accessor.count);
                    while (it.next()) |idxx| {
                        // _ = idxx;
                        // try indices.insertSlice(self.allocator, initial_vertex, idxx);
                        try indices.appendSlice(self.allocator, idxx);
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
                                try vertices.resize(self.allocator, vertices.items.len + accessor.count);
                                while (it.next()) |v| {
                                    try vertices.append(self.allocator, .{
                                        .pos = .{ v[0], v[1], v[2] },
                                        .normal = .{ 1, 0, 0 },
                                        .col = .{ 1, 1, 1, 1 },
                                        .uv_x = 0,
                                        .uv_y = 0,
                                    });
                                }
                            },
                            .normal => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |n| : (i += 1) {
                                    vertices.items[initial_vertex + i].normal = .{ n[0], n[1], n[2] };
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

        try mesh.uploadMesh(ctx, cmd_pool, try vertices.toOwnedSlice(self.allocator), try indices.toOwnedSlice(self.allocator));

        meshes.appendAssumeCapacity(mesh);
    }

    return meshes;
}
