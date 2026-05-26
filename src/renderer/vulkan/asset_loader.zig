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
// zgltf.glb_binary is a SLICE into the input file buffer — it doesn't copy.
// Retain ownership here so the slice stays valid for the lifetime of the
// AssetLoader (which is also the lifetime of any GPU buffer we upload from it).
file_buffers: std.ArrayList([]align(4) u8),

pub fn init(allocator: std.mem.Allocator) AssetLoader {
    return .{
        .allocator = allocator,
        .zgltf = Gltf.init(allocator),
        .file_buffers = .{},
    };
}

pub fn deinit(self: *AssetLoader) void {
    self.zgltf.deinit();
    for (self.file_buffers.items) |buf| self.allocator.free(buf);
    self.file_buffers.deinit(self.allocator);
}

pub fn loadGlb(self: *AssetLoader, glb_filename: []const u8) !Gltf.Data {
    assert(std.mem.eql(u8, std.fs.path.extension(glb_filename), ".glb"));
    log.info("Parse GLB file: {s}", .{glb_filename});

    const buffer = try std.fs.cwd().readFileAllocOptions(self.allocator, glb_filename, 512_000, null, .@"4", null);
    // DO NOT free here — zgltf retains a slice into this buffer.
    try self.file_buffers.append(self.allocator, buffer);

    try self.zgltf.parse(buffer);
    // ================== DEBUG ===============
    self.zgltf.debugPrint();
    // ==================================

    return self.zgltf.data;
}

pub fn loadGltf(self: *AssetLoader, gltf_filename: []const u8) !Gltf.Data {
    assert(std.mem.eql(u8, std.fs.path.extension(gltf_filename), ".gltf"));
    log.info("Parse GLTF file: {s}", .{gltf_filename});

    const buffer = try std.fs.cwd().readFileAllocOptions(self.allocator, gltf_filename, 512_000, null, .@"4", null);
    // DO NOT free here — zgltf retains a slice into this buffer.
    try self.file_buffers.append(self.allocator, buffer);

    try self.zgltf.parse(buffer);
    // ================== DEBUG ===============
    self.zgltf.debugPrint();
    // ==================================

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
                    // Append only — don't resize+append (would double the buffer
                    // with garbage front-padding and shift the real indices).
                    while (it.next()) |idxx| {
                        try indices.appendSlice(self.allocator, idxx);
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
                            bv_idx, bv.byte_offset, bv.byte_length, bv.byte_stride,
                        });
                    }
                    // ==================================
                    for (primitive.attributes) |attribute| {
                        switch (attribute) {
                            .position => |idx| {
                                const accessor = data.accessors[idx];
                                const bv = self.zgltf.data.buffer_views[accessor.buffer_view.?];
                                const byte_off = bv.byte_offset + accessor.byte_offset;
                                // ================== DEBUG ===============
                                std.debug.print("  [ITER-DBG] .position acc[{d}] bufView={d} byte_off={d} bin.len={d} bin.ptr=0x{x}\n", .{
                                    idx, accessor.buffer_view.?, byte_off, bin.len, @intFromPtr(bin.ptr),
                                });
                                if (byte_off + 12 <= bin.len) {
                                    const raw = bin[byte_off .. byte_off + 12];
                                    const x = @as(f32, @bitCast(std.mem.readInt(u32, raw[0..4], .little)));
                                    const y = @as(f32, @bitCast(std.mem.readInt(u32, raw[4..8], .little)));
                                    const z = @as(f32, @bitCast(std.mem.readInt(u32, raw[8..12], .little)));
                                    std.debug.print("  [ITER-DBG] raw bytes at bin[{d}]: {x} {x} {x} → ({d:.4},{d:.4},{d:.4})\n", .{
                                        byte_off, raw[0..4].*, raw[4..8].*, raw[8..12].*,
                                        x, y, z,
                                    });
                                }
                                var dbg_first = true;
                                // ==================================
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                while (it.next()) |v| {
                                    // ================== DEBUG ===============
                                    if (dbg_first) {
                                        std.debug.print("  [ITER-DBG] iterator first result: ({d:.4},{d:.4},{d:.4})\n", .{ v[0], v[1], v[2] });
                                    }
                                    // ==================================
                                    try vertices.append(self.allocator, .{
                                        .pos = .{ v[0], v[1], v[2] },
                                        .normal = .{ 0, 0, 1 },
                                        // Bright orange so GLB-loaded meshes are visually
                                        // distinct from the white selftest/cube meshes.
                                        .col = .{ 1.0, 0.5, 0.0, 1.0 },
                                        .uv_x = 0,
                                        .uv_y = 0,
                                    });
                                    // ================== DEBUG ===============
                                    if (dbg_first) {
                                        const vx = vertices.items[vertices.items.len - 1];
                                        std.debug.print("  [ITER-DBG] vertex[0] pos AFTER append: ({d:.4},{d:.4},{d:.4})\n", .{ vx.pos[0], vx.pos[1], vx.pos[2] });
                                        dbg_first = false;
                                    }
                                    // ==================================
                                }
                            },
                            .normal => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |v| : (i += 1) {
                                    // ================== DEBUG ===============
                                    if (i == 0) std.debug.print("  [ITER-DBG] BEFORE normal[0] write: pos=({d:.4},{d:.4},{d:.4})\n", .{ vertices.items[initial_vertex].pos[0], vertices.items[initial_vertex].pos[1], vertices.items[initial_vertex].pos[2] });
                                    // ==================================
                                    vertices.items[initial_vertex + i].normal = .{ v[0], v[1], v[2] };
                                    // ================== DEBUG ===============
                                    if (i == 0) std.debug.print("  [ITER-DBG] AFTER  normal[0] write ({d:.4},{d:.4},{d:.4}): pos=({d:.4},{d:.4},{d:.4})\n", .{ v[0], v[1], v[2], vertices.items[initial_vertex].pos[0], vertices.items[initial_vertex].pos[1], vertices.items[initial_vertex].pos[2] });
                                    // ==================================
                                }
                            },
                            .texcoord => |idx| {
                                const accessor = data.accessors[idx];
                                var it = accessor.iterator(f32, &self.zgltf, bin);
                                var i: u32 = 0;
                                while (it.next()) |uv| : (i += 1) {
                                    // ================== DEBUG ===============
                                    if (i == 0) std.debug.print("  [ITER-DBG] BEFORE texcoord[0] write: pos=({d:.4},{d:.4},{d:.4})\n", .{ vertices.items[initial_vertex].pos[0], vertices.items[initial_vertex].pos[1], vertices.items[initial_vertex].pos[2] });
                                    // ==================================
                                    vertices.items[initial_vertex + i].uv_x = uv[0];
                                    vertices.items[initial_vertex + i].uv_y = uv[1];
                                    // ================== DEBUG ===============
                                    if (i == 0) std.debug.print("  [ITER-DBG] AFTER  texcoord[0] write ({d:.4},{d:.4}): pos=({d:.4},{d:.4},{d:.4})\n", .{ uv[0], uv[1], vertices.items[initial_vertex].pos[0], vertices.items[initial_vertex].pos[1], vertices.items[initial_vertex].pos[2] });
                                    // ==================================
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

        // ================== DEBUG ===============
        if (vertices.items.len > 0 and indices.items.len > 0) {
            const first_v = vertices.items[0];
            const last_v = vertices.items[vertices.items.len - 1];
            var max_idx: u32 = 0;
            var min_idx: u32 = std.math.maxInt(u32);
            for (indices.items) |idx| {
                if (idx > max_idx) max_idx = idx;
                if (idx < min_idx) min_idx = idx;
            }
            // Compute bounding box of all positions so we can verify the mesh
            // is in a reasonable world-space region.
            var min_p: [3]f32 = .{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
            var max_p: [3]f32 = .{ -std.math.floatMax(f32), -std.math.floatMax(f32), -std.math.floatMax(f32) };
            for (vertices.items) |v| {
                for (0..3) |k| {
                    if (v.pos[k] < min_p[k]) min_p[k] = v.pos[k];
                    if (v.pos[k] > max_p[k]) max_p[k] = v.pos[k];
                }
            }
            std.debug.print(
                \\[SELFTEST-loader] mesh "{s}"
                \\  vertex_count = {d}, index_count = {d}
                \\  first vertex pos = ({d:.3}, {d:.3}, {d:.3}), color = ({d:.2}, {d:.2}, {d:.2}, {d:.2})
                \\  last  vertex pos = ({d:.3}, {d:.3}, {d:.3})
                \\  bounding box  min = ({d:.3}, {d:.3}, {d:.3}), max = ({d:.3}, {d:.3}, {d:.3})
                \\  index range = [{d} .. {d}] (must be < vertex_count={d})
                \\  first 3 indices = {d} {d} {d}
                \\  surface[0] start_index={d} count={d}
                \\  @sizeOf(Vertex)={d}, @alignOf(Vertex)={d}, slice len in bytes = {d}
                \\
            , .{
                mesh.name,
                vertices.items.len, indices.items.len,
                first_v.pos[0], first_v.pos[1], first_v.pos[2],
                first_v.col[0], first_v.col[1], first_v.col[2], first_v.col[3],
                last_v.pos[0], last_v.pos[1], last_v.pos[2],
                min_p[0], min_p[1], min_p[2], max_p[0], max_p[1], max_p[2],
                min_idx, max_idx, vertices.items.len,
                indices.items[0], indices.items[1], indices.items[2],
                mesh.surfaces.items[0].start_index, mesh.surfaces.items[0].count,
                @sizeOf(Data.Vertex), @alignOf(Data.Vertex), std.mem.sliceAsBytes(vertices.items).len,
            });
            // Dump the raw bytes of vertex 0 so we can compare with the expected layout.
            const v0_bytes = std.mem.asBytes(&vertices.items[0]);
            std.debug.print("  vertex0 raw bytes (len={d}):", .{v0_bytes.len});
            for (v0_bytes, 0..) |b, k| {
                if (k % 4 == 0) std.debug.print(" ", .{});
                std.debug.print("{x:0>2}", .{b});
            }
            std.debug.print("\n", .{});
            // Print position + magnitude of first 8 (or all if fewer) vertices.
            // Magnitude ~1.0 for ALL vertices suggests we read normals not positions.
            const n = @min(vertices.items.len, 8);
            std.debug.print("  first {d} vertex positions (with magnitude):\n", .{n});
            for (vertices.items[0..n], 0..) |v, k| {
                const mag = std.math.sqrt(v.pos[0] * v.pos[0] + v.pos[1] * v.pos[1] + v.pos[2] * v.pos[2]);
                std.debug.print("    [{d}] = ({d:.3}, {d:.3}, {d:.3})  |mag|={d:.3}\n", .{ k, v.pos[0], v.pos[1], v.pos[2], mag });
            }
            if (max_idx >= vertices.items.len) {
                std.debug.print("[SELFTEST-loader] !!! INDEX OUT OF RANGE: max_idx={d} >= vertex_count={d}\n", .{ max_idx, vertices.items.len });
            }
            // Print vertex positions referenced by the FIRST TRIANGLE's actual indices.
            // This verifies that the loaded positions match expected GLTF world-space coords,
            // not normals (which would all have |mag|~1.0).
            if (indices.items.len >= 3) {
                const idx0 = indices.items[0];
                const idx1 = indices.items[1];
                const idx2 = indices.items[2];
                std.debug.print("  first triangle indices: [{d}, {d}, {d}]\n", .{ idx0, idx1, idx2 });
                if (idx0 < vertices.items.len) {
                    const p = vertices.items[idx0].pos;
                    std.debug.print("    vtx[{d}] pos=({d:.4},{d:.4},{d:.4})\n", .{ idx0, p[0], p[1], p[2] });
                }
                if (idx1 < vertices.items.len) {
                    const p = vertices.items[idx1].pos;
                    std.debug.print("    vtx[{d}] pos=({d:.4},{d:.4},{d:.4})\n", .{ idx1, p[0], p[1], p[2] });
                }
                if (idx2 < vertices.items.len) {
                    const p = vertices.items[idx2].pos;
                    std.debug.print("    vtx[{d}] pos=({d:.4},{d:.4},{d:.4})\n", .{ idx2, p[0], p[1], p[2] });
                }
            }
        }
        // ==================================

        try mesh.uploadMesh(ctx, cmd_pool, try vertices.toOwnedSlice(self.allocator), try indices.toOwnedSlice(self.allocator));

        meshes.appendAssumeCapacity(mesh);
    }

    return meshes;
}
