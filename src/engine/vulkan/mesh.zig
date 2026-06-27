// The mesh assume indice u16,

const std = @import("std");
const log = std.log.scoped(.mesh);
const assert = std.debug.assert;
const vk = @import("vulkan");
const sdl = @import("sdl3");
const zm = @import("zmath");

const Engine = @import("engine.zig");
const Buffer = @import("buffer.zig");
const VulkanCommand = @import("command_pool.zig");
const CommandPool = VulkanCommand.CommandPool;
const GpuCommand = VulkanCommand.GpuCommand;
const AllocatedCommandBuffer = VulkanCommand.AllocatedCommandBuffer;
const ImmediateCommands = VulkanCommand.ImmediateCommands;
const Image = @import("image.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");
const Vertex = @import("../graphics/buffers.zig").Vertex;
const MaterialInstance = @import("../graphics/materials.zig").MaterialInstance;
const Bounds = @import("../graphics/objects.zig").Bounds;

const Mesh = @This();

pub const MeshBuffers = struct {
    index: ?Buffer = null,
    vertex: ?Buffer = null,
    // storage: ?Buffer = null,
};

pub const GLTFMaterial = struct {
    data: MaterialInstance,
};

pub const GeoSurface = struct {
    start_index: u32 = 0,
    count: u32 = 0,
    material: ?*GLTFMaterial = null,
    bounds: Bounds = .{},
};

allocator: std.mem.Allocator,

// image: ?Image = null,

name: []const u8,
buffers: MeshBuffers = .{},

// constants: ?PushConstants = null,
surfaces: std.ArrayList(GeoSurface),

pub fn init(allocator: std.mem.Allocator) !Mesh {
    return .{ .allocator = allocator, .name = "New Mesh", .surfaces = try .initCapacity(allocator, 0) };
}

pub fn uploadMesh(
    self: *Mesh,
    engine: *Engine,
    vertices: []const Vertex,
    indices: []const u32,
) !void {
    const vertice_bytes = std.mem.sliceAsBytes(vertices);
    const indice_bytes = std.mem.sliceAsBytes(indices);

    try self.setVerticeBuffer(engine.ctx, @intCast(vertice_bytes.len));
    try self.setIndiceBuffer(engine.ctx, @intCast(indice_bytes.len));

    var immediate_cmd = try ImmediateCommands.init(engine, engine.getCurrentFrame().cmd_pool);
    defer immediate_cmd.deinit(engine);

    var gpu_cmd = try TransferBuffersCmd.create(self, engine, &immediate_cmd.buffer, vertice_bytes, indice_bytes);
    defer gpu_cmd.destroy();

    try immediate_cmd.addCommand(engine.allocator, gpu_cmd.interface());

    try engine.immediateSubmit(.graphic, immediate_cmd);
}

// Helper Creation function for a Quad Mesh
pub fn makeTriangleMesh(allocator: std.mem.Allocator, ctx: *const GraphicsContext, cmd_pool: *const CommandPool, vertices: [3]Vertex) !Mesh {
    var mesh = try Mesh.init(allocator);
    mesh.name = "Simple Triangle";

    const vertice_bytes = std.mem.sliceAsBytes(&vertices);
    try mesh.setVerticeBuffer(ctx, @intCast(vertice_bytes.len));
    try mesh.buffers.vertex.?.fastTransferOffset(ctx, cmd_pool, vertice_bytes, 0, 0);

    return mesh;
}

fn setVerticeBuffer(self: *Mesh, ctx: *const GraphicsContext, len: u32) !void {
    self.buffers.vertex = try Buffer.create(ctx, len, .{
        .storage_buffer_bit = true,
        .transfer_dst_bit = true,
        .shader_device_address_bit = true,
    }, .{ .device_local_bit = true });
}

// pub fn setStorageVertices(self: *Mesh, ctx: *const GraphicsContext, cmd_pool: *const CommandPool, vertices: []const u8) !void {
//     self.buffers.storage = try Buffer.create(ctx, @intCast(vertices.len), .{
//         .storage_buffer_bit = true,
//         .transfer_dst_bit = true,
//         .shader_device_address_bit = true,
//     }, .{ .device_local_bit = true });
//     try self.buffers.storage.?.fastTransfer(ctx, cmd_pool, vertices);
// }

fn setIndiceBuffer(self: *Mesh, ctx: *const GraphicsContext, len: u32) !void {
    self.buffers.index = try Buffer.create(ctx, len, .{
        .index_buffer_bit = true,
        .transfer_dst_bit = true,
        .transfer_src_bit = true,
    }, .{ .device_local_bit = true });
}

pub const TransferBuffersCmd = struct {
    staging_buffer: Buffer,
    vertice_bytes: []const u8,
    indice_bytes: []const u8,
    mesh: *const Mesh,
    engine: *Engine,
    cmd_buffer: *AllocatedCommandBuffer,

    pub fn create(mesh: *const Mesh, engine: *Engine, cmd_buffer: *AllocatedCommandBuffer, vertice_bytes: []const u8, indice_bytes: []const u8) !TransferBuffersCmd {
        var staging_buffer = try Buffer.create(
            engine.ctx,
            @intCast(vertice_bytes.len + indice_bytes.len),
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );

        try staging_buffer.copyInto(engine.ctx, vertice_bytes, 0);
        try staging_buffer.copyInto(engine.ctx, indice_bytes, vertice_bytes.len);

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
        self.staging_buffer.destroy(self.engine.ctx);
    }

    pub fn execute(self: *TransferBuffersCmd, engine: *Engine) void {
        if (self.mesh.buffers.vertex != null) {
            const vertex_copy = [_]vk.BufferCopy{.{
                .src_offset = 0,
                .dst_offset = 0,
                .size = self.vertice_bytes.len,
            }};
            engine.ctx.device.cmdCopyBuffer(self.cmd_buffer.vk_command_buffer, self.staging_buffer.vk_buffer, self.mesh.buffers.vertex.?.vk_buffer, &vertex_copy);

            log.info("Copy Mesh {} bytes of vertices into VB addr {}", .{ self.vertice_bytes.len, self.mesh.buffers.vertex.?.address.? });
        }

        if (self.mesh.buffers.index != null) {
            const index_copy = [_]vk.BufferCopy{.{
                .src_offset = self.vertice_bytes.len,
                .dst_offset = 0,
                .size = self.indice_bytes.len,
            }};
            engine.ctx.device.cmdCopyBuffer(self.cmd_buffer.vk_command_buffer, self.staging_buffer.vk_buffer, self.mesh.buffers.index.?.vk_buffer, &index_copy);
            log.info("Copy Mesh {} bytes of indices from offset {}", .{ self.indice_bytes.len, self.vertice_bytes.len });
        }
    }

    pub fn interface(self: *TransferBuffersCmd) GpuCommand {
        return GpuCommand.interface(self);
    }
};

pub fn destroy(self: *Mesh, ctx: *const GraphicsContext) void {
    if (self.buffers.vertex) |*vb| {
        vb.destroy(ctx);
    }
    if (self.buffers.index) |*vi| {
        vi.destroy(ctx);
    }

    self.surfaces.deinit(self.allocator);
}
