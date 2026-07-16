const std = @import("std");
const log = std.log.scoped(.resource_mesh);
const assert = std.debug.assert;

const vk = @import("vulkan");
const zm = @import("zmath");

const Config = @import("../config.zig");
const Vertex = @import("../engine/graphics/buffers.zig").Vertex;
const Buffer = @import("../engine/vulkan/buffer.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const AssetManager = @import("manager.zig");
const Resource = @import("resource.zig").Resource;
const Material = @import("material.zig").Material;
const Gltf = @import("zgltf").Gltf;
const VulkanCommand = @import("../engine/vulkan/command_pool.zig");
const GpuCommand = VulkanCommand.GpuCommand;
const AllocatedCommandBuffer = VulkanCommand.AllocatedCommandBuffer;
const ImmediateCommands = VulkanCommand.ImmediateCommands;

const Vertices = std.ArrayList(Vertex);
const Indices = std.ArrayList(u32);

const MESH_BASE_FOLDER_PATH = "assets/models/";

const MeshBuffers = struct {
    index: Buffer,
    index_count: u32 = 0,

    vertex: Buffer,
    vertex_count: u32 = 0,

    pub fn destroy(self: *MeshBuffers) void {
        self.vertex.destroy();
        self.index.destroy();
    }
};

pub const Surface = struct {
    start_index: u32 = 0,
    count: u32 = 0,
    material_index: ?u32 = null, // Raw GLTF primitive.material
    material: ?*Material = null, // Filled in bindMaterials
    bounds: Bounds = .{},
};

pub const Bounds = struct {
    origin: [3]f32 = .{ 0, 0, 0 },
    sphere_radius: f32 = 0,
    extents: [3]f32 = .{ 0, 0, 0 },
};

/// Implementation of the Vulkan Mesh Resource that is managed by the Resource manager
pub const Mesh = struct {
    id: []const u8,
    source: Source,

    buffers: MeshBuffers = undefined,

    /// Contains data about each surfaces
    surfaces: std.ArrayList(Surface) = .empty,

    pub const Source = union(enum) {
        gltf_item: struct { gltf: *Gltf, mesh_idx: u32 },
    };

    pub fn interface(self: *Mesh) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: []const u8, source: Source) Mesh {
        return .{
            .id = id,
            .source = source,
        };
    }

    pub fn getId(self: *const Mesh) []const u8 {
        return self.id;
    }

    pub fn load(self: *Mesh, mgr: *AssetManager) !void {
        const engine = mgr.engine;
        var vertices = Vertices.empty;
        defer vertices.deinit(engine.allocator);
        var indices = Indices.empty;
        defer indices.deinit(engine.allocator);

        try self.loadMeshData(engine.allocator, &vertices, &indices);

        const vertex_count: u32 = @intCast(vertices.items.len);
        const index_count: u32 = @intCast(indices.items.len);

        const v_buffer = try createVertexBuffer(engine, vertex_count * @sizeOf(Vertex));
        const i_buffer = try createIndexBuffer(engine, index_count * @sizeOf(u32));

        self.buffers = .{
            .index = i_buffer,
            .index_count = index_count,

            .vertex = v_buffer,
            .vertex_count = vertex_count,
        };

        try self.upload(engine, &vertices, &indices);
    }

    pub fn unload(self: *Mesh, mgr: *AssetManager) void {
        self.buffers.destroy();
        self.surfaces.deinit(mgr.engine.allocator);
    }

    pub fn bindMaterials(self: *Mesh, materials: []const *Material) void {
        for (self.surfaces.items) |*surface| {
            if (surface.material_index) |idx| {
                surface.material = materials[idx];
            } else if (materials.len > 0) {
                // Primitive without a material: fall back to the file's
                // first material (matches the pre-refactor behavior).
                surface.material = materials[0];
            }
        }
    }

    /// Upload to GPU
    fn upload(self: *Mesh, engine: *Engine, vertices: *const Vertices, indices: *const Indices) !void {
        var immediate_cmd = try ImmediateCommands.init(engine, engine.getCurrentFrame().cmd_pool);
        defer immediate_cmd.deinit(engine);

        var gpu_cmd = try TransferBuffersCmd.create(self, engine, &immediate_cmd.buffer, std.mem.sliceAsBytes(vertices.items), std.mem.sliceAsBytes(indices.items));
        defer gpu_cmd.destroy();

        try immediate_cmd.addCommand(engine.allocator, gpu_cmd.interface());

        try engine.immediateSubmit(.graphic, immediate_cmd);
    }

    fn createVertexBuffer(engine: *Engine, size: u32) !Buffer {
        return try Buffer.create(engine, size, .{
            .storage_buffer_bit = true,
            .transfer_dst_bit = true,
            .shader_device_address_bit = true,
        }, .{ .device_local_bit = true });
    }

    fn createIndexBuffer(engine: *Engine, size: u32) !Buffer {
        return try Buffer.create(engine, size, .{
            .index_buffer_bit = true,
            .transfer_dst_bit = true,
            .shader_device_address_bit = true,
        }, .{ .device_local_bit = true });
    }

    // Implementation using tinygltf or similar library
    // This method handles the complex task of:
    // - Opening and validating the mesh file format
    // - Parsing vertex attributes (positions, normals, UVs, etc.)
    // - Extracting index data that defines triangle connectivity
    // - Converting from file format to engine-specific vertex structures
    // - Performing validation to ensure data integrity
    // ...
    fn loadMeshData(self: *Mesh, allocator: std.mem.Allocator, vertices: *Vertices, indices: *Indices) !void {
        switch (self.source) {
            .gltf_item => |source| {
                const gltf = source.gltf;
                const gltf_mesh = gltf.data.meshes[source.mesh_idx];

                if (null == gltf.glb_binary) return error.GlbBinaryEmpty;
                const glb_binary = gltf.glb_binary.?;

                // for (gltf.data.meshes, 0..) |mesh, j| {

                indices.clearRetainingCapacity();
                vertices.clearRetainingCapacity();

                for (gltf_mesh.primitives) |primitive| {
                    if (primitive.indices == null) {
                        continue;
                    }
                    const primitive_index = primitive.indices.?;

                    var surface: Surface = .{
                        .start_index = @intCast(indices.items.len),
                        .count = @intCast(gltf.data.accessors[primitive_index].count),
                        .material_index = if (primitive.material) |i| @intCast(i) else null,
                    };

                    // if (primitive.material) |mat_idx| {
                    //     new_surface.material = self.pool._materials.items[initial_material_index + mat_idx];
                    // } else {
                    //     new_surface.material = self.pool._materials.items[initial_material_index];
                    // }

                    const initial_vertex = vertices.items.len;

                    { // load indexes
                        const accessor = gltf.data.accessors[primitive_index];
                        switch (accessor.component_type) {
                            .unsigned_integer => {
                                var it = accessor.iterator(u32, gltf, glb_binary);

                                while (it.next()) |idxx| {
                                    for (idxx) |v| {
                                        try indices.append(allocator, @intCast(v + initial_vertex));
                                    }
                                }
                            },
                            else => {
                                var it = accessor.iterator(u16, gltf, glb_binary);

                                while (it.next()) |idxx| {
                                    for (idxx) |v| {
                                        try indices.append(allocator, @intCast(v + initial_vertex));
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
                                    var it = accessor.iterator(f32, gltf, glb_binary);
                                    while (it.next()) |v| {
                                        try vertices.append(allocator, .{
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
                                    var it = accessor.iterator(f32, gltf, glb_binary);
                                    var i: u32 = 0;
                                    while (it.next()) |v| : (i += 1) {
                                        vertices.items[initial_vertex + i].normal = .{ v[0], v[1], v[2] };
                                    }
                                },
                                .tangent => |idx| {
                                    const accessor = gltf.data.accessors[idx];
                                    var it = accessor.iterator(f32, gltf, glb_binary);
                                    var i: u32 = 0;
                                    while (it.next()) |t| : (i += 1) {
                                        vertices.items[initial_vertex + i].tangent = .{ t[0], t[1], t[2] };
                                    }
                                },
                                .texcoord => |idx| {
                                    const accessor = gltf.data.accessors[idx];
                                    var it = accessor.iterator(f32, gltf, glb_binary);
                                    var i: u32 = 0;
                                    while (it.next()) |uv| : (i += 1) {
                                        vertices.items[initial_vertex + i].uv_x = uv[0];
                                        vertices.items[initial_vertex + i].uv_y = uv[1];
                                    }
                                },
                                .color => |idx| {
                                    const accessor = gltf.data.accessors[idx];
                                    var it = accessor.iterator(f32, gltf, glb_binary);
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

                        surface.bounds = .{
                            .origin = origin,
                            .extents = extents,
                            .sphere_radius = zm.length3(.{ extents[0], extents[1], extents[2], 0 })[0],
                        };
                    }

                    try self.surfaces.append(allocator, surface);
                }
            },
        }
    }
};

const TransferBuffersCmd = struct {
    staging_buffer: Buffer,
    vertice_bytes: []const u8,
    indice_bytes: []const u8,
    mesh: *const Mesh,
    engine: *Engine,
    cmd_buffer: *AllocatedCommandBuffer,

    pub fn create(mesh: *const Mesh, engine: *Engine, cmd_buffer: *AllocatedCommandBuffer, vertice_bytes: []const u8, indice_bytes: []const u8) !TransferBuffersCmd {
        var staging_buffer = try Buffer.create(
            engine,
            @intCast(vertice_bytes.len + indice_bytes.len),
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );

        try staging_buffer.copyInto(vertice_bytes, 0);
        try staging_buffer.copyInto(indice_bytes, vertice_bytes.len);

        return .{
            .engine = engine,
            .staging_buffer = staging_buffer,
            .vertice_bytes = vertice_bytes,
            .indice_bytes = indice_bytes,
            .mesh = mesh,
            .cmd_buffer = cmd_buffer,
        };
    }

    pub fn destroy(self: *TransferBuffersCmd) void {
        self.staging_buffer.destroy();
    }

    pub fn execute(self: *TransferBuffersCmd, engine: *Engine) void {
        const vertex_copy = [_]vk.BufferCopy{.{
            .src_offset = 0,
            .dst_offset = 0,
            .size = self.vertice_bytes.len,
        }};
        engine.ctx.device.cmdCopyBuffer(self.cmd_buffer.vk_command_buffer, self.staging_buffer.vk_buffer, self.mesh.buffers.vertex.vk_buffer, &vertex_copy);

        if (Config.log.mesh) {
            log.info("Copy Mesh {} bytes of vertices into VB addr {}", .{ self.vertice_bytes.len, self.mesh.buffers.vertex.address.? });
        }

        const index_copy = [_]vk.BufferCopy{.{
            .src_offset = self.vertice_bytes.len,
            .dst_offset = 0,
            .size = self.indice_bytes.len,
        }};
        engine.ctx.device.cmdCopyBuffer(self.cmd_buffer.vk_command_buffer, self.staging_buffer.vk_buffer, self.mesh.buffers.index.vk_buffer, &index_copy);
        if (Config.log.mesh) {
            log.info("Copy Mesh {} bytes of indices from offset {}", .{ self.indice_bytes.len, self.vertice_bytes.len });
        }
    }

    pub fn interface(self: *TransferBuffersCmd) GpuCommand {
        return GpuCommand.interface(self);
    }
};
