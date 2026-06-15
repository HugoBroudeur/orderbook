// The mesh assume indice u16,

const std = @import("std");
const log = std.log.scoped(.mesh);
const assert = std.debug.assert;
const vk = @import("vulkan");
const sdl = @import("sdl3");
const zm = @import("zmath");

const Engine = @import("engine.zig");
const Buffer = @import("buffer.zig");
const CommandPool = @import("command_pool.zig");
const Image = @import("image.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");
const Vertex = @import("../graphics/buffers.zig").Vertex;
const MaterialInstance = @import("../graphics/materials.zig").MaterialInstance;

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

// pub fn uploadMesh(ctx: *const GraphicsContext, cmd_pool: *const CommandPool, vertices: []const u8, indices: []const u32) !Mesh {}

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

    var cmd = try TransferBuffersCmd.create(self, engine.ctx, vertice_bytes, indice_bytes);
    try engine.getCurrentFrame().cmd_pool.immediateSubmit(engine.ctx, .graphic, &.{cmd.interface()});
    cmd.destroy();

    // // READBACK TEST: Create a readback buffer and verify index data
    // var readback_buffer = try Buffer.create(
    //     ctx,
    //     @intCast(indice_bytes.len),
    //     .{ .transfer_dst_bit = true },
    //     .{ .host_visible_bit = true, .host_coherent_bit = true },
    // );
    // defer readback_buffer.destroy(ctx);
    //
    // // Copy index buffer to readback buffer
    // const alloc_info = vk.CommandBufferAllocateInfo{
    //     .level = .primary,
    //     .command_pool = cmd_pool.vk_cmd_pool,
    //     .command_buffer_count = 1,
    // };
    // var command_buffer: vk.CommandBuffer = undefined;
    // try ctx.device.allocateCommandBuffers(&alloc_info, @ptrCast(&command_buffer));
    // defer ctx.device.freeCommandBuffers(cmd_pool.vk_cmd_pool, 1, @ptrCast(&command_buffer));
    //
    // try ctx.device.beginCommandBuffer(command_buffer, &.{ .flags = .{ .one_time_submit_bit = true } });
    // const copy_region = vk.BufferCopy{ .src_offset = 0, .dst_offset = 0, .size = indice_bytes.len };
    // ctx.device.cmdCopyBuffer(command_buffer, self.buffers.index.?.vk_buffer, readback_buffer.vk_buffer, 1, @ptrCast(&copy_region));
    // try ctx.device.endCommandBuffer(command_buffer);
    //
    // const submit_info = vk.SubmitInfo{
    //     .command_buffer_count = 1,
    //     .p_command_buffers = @ptrCast(&command_buffer),
    //     .wait_semaphore_count = 0,
    //     .p_wait_semaphores = undefined,
    //     .p_wait_dst_stage_mask = undefined,
    //     .signal_semaphore_count = 0,
    //     .p_signal_semaphores = undefined,
    // };
    // try ctx.device.queueSubmit(ctx.graphics_queue.handle, 1, @ptrCast(&submit_info), .null_handle);
    // try ctx.device.queueWaitIdle(ctx.graphics_queue.handle);
    //
    // // Read back and verify
    // if (false) { // For debug
    //     const data = try ctx.device.mapMemory(readback_buffer.memory, 0, vk.WHOLE_SIZE, .{});
    //     defer ctx.device.unmapMemory(readback_buffer.memory);
    //     const readback_indices = @as([*]const u8, @ptrCast(data))[0..indice_bytes.len];
    //     log.info("Index buffer readback: {any}", .{readback_indices});
    //     log.info("Expected: {any}", .{indice_bytes});
    // }
}

// Helper Creation function for a Quad Mesh
pub fn makeQuadMesh(
    allocator: std.mem.Allocator,
    ctx: *const GraphicsContext,
    cmd_pool: *const CommandPool,
    vertices: [4]Vertex,
    indices: []const u32,
) !Mesh {
    var mesh = try Mesh.init(allocator);
    mesh.name = "Simple Texture Quad";

    const vertice_bytes = std.mem.sliceAsBytes(&vertices);
    const indice_bytes = std.mem.sliceAsBytes(indices);
    log.info("Index bytes: {any}", .{indice_bytes});

    try mesh.setVerticeBuffer(ctx, @intCast(vertice_bytes.len));
    try mesh.setIndiceBuffer(ctx, @intCast(indice_bytes.len));

    var cmd = try TransferBuffersCmd.create(&mesh, ctx, vertice_bytes, indice_bytes);
    try cmd_pool.immediateSubmit(ctx, .graphic, &.{cmd.interface()});
    cmd.destroy();

    // // READBACK TEST: Create a readback buffer and verify index data
    // var readback_buffer = try Buffer.create(
    //     ctx,
    //     @intCast(indice_bytes.len),
    //     .{ .transfer_dst_bit = true },
    //     .{ .host_visible_bit = true, .host_coherent_bit = true },
    // );
    // defer readback_buffer.destroy(ctx);
    //
    // // Copy index buffer to readback buffer
    // const alloc_info = vk.CommandBufferAllocateInfo{
    //     .level = .primary,
    //     .command_pool = cmd_pool.vk_cmd_pool,
    //     .command_buffer_count = 1,
    // };
    // var command_buffer: vk.CommandBuffer = undefined;
    // try ctx.device.allocateCommandBuffers(&alloc_info, @ptrCast(&command_buffer));
    // defer ctx.device.freeCommandBuffers(cmd_pool.vk_cmd_pool, 1, @ptrCast(&command_buffer));
    //
    // try ctx.device.beginCommandBuffer(command_buffer, &.{ .flags = .{ .one_time_submit_bit = true } });
    // const copy_region = vk.BufferCopy{ .src_offset = 0, .dst_offset = 0, .size = indice_bytes.len };
    // ctx.device.cmdCopyBuffer(command_buffer, mesh.buffers.index.?.vk_buffer, readback_buffer.vk_buffer, 1, @ptrCast(&copy_region));
    // try ctx.device.endCommandBuffer(command_buffer);
    //
    // const submit_info = vk.SubmitInfo{
    //     .command_buffer_count = 1,
    //     .p_command_buffers = @ptrCast(&command_buffer),
    //     .wait_semaphore_count = 0,
    //     .p_wait_semaphores = undefined,
    //     .p_wait_dst_stage_mask = undefined,
    //     .signal_semaphore_count = 0,
    //     .p_signal_semaphores = undefined,
    // };
    // try ctx.device.queueSubmit(ctx.graphics_queue.handle, 1, @ptrCast(&submit_info), .null_handle);
    // try ctx.device.queueWaitIdle(ctx.graphics_queue.handle);
    //
    // // Read back and verify
    // if (true) { // For debug
    //     const data = try ctx.device.mapMemory(readback_buffer.memory, 0, vk.WHOLE_SIZE, .{});
    //     defer ctx.device.unmapMemory(readback_buffer.memory);
    //     const readback_indices = @as([*]const u8, @ptrCast(data))[0..indice_bytes.len];
    //     log.info("Index buffer readback: {any}", .{readback_indices});
    //     log.info("Expected: {any}", .{indice_bytes});
    // }

    return mesh;
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
    ctx: *const GraphicsContext,
    mesh: *const Mesh,

    pub fn create(mesh: *const Mesh, ctx: *const GraphicsContext, vertice_bytes: []const u8, indice_bytes: []const u8) !TransferBuffersCmd {
        var staging_buffer = try Buffer.create(
            ctx,
            @intCast(vertice_bytes.len + indice_bytes.len),
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );

        try staging_buffer.copyInto(ctx, vertice_bytes, 0);
        try staging_buffer.copyInto(ctx, indice_bytes, vertice_bytes.len);

        return .{
            .ctx = ctx,
            .staging_buffer = staging_buffer,
            .vertice_bytes = vertice_bytes,
            .indice_bytes = indice_bytes,
            .mesh = mesh,
        };
    }

    pub fn destroy(self: *TransferBuffersCmd) void {
        self.staging_buffer.destroy(self.ctx);
    }

    pub fn execute(self: *TransferBuffersCmd, cmd: vk.CommandBuffer) void {
        if (self.mesh.buffers.vertex != null) {
            const vertex_copy = [_]vk.BufferCopy{.{
                .src_offset = 0,
                .dst_offset = 0,
                .size = self.vertice_bytes.len,
            }};
            self.ctx.device.cmdCopyBuffer(cmd, self.staging_buffer.vk_buffer, self.mesh.buffers.vertex.?.vk_buffer, &vertex_copy);

            log.info("Copy Mesh {} bytes of vertices into VB addr {}", .{ self.vertice_bytes.len, self.mesh.buffers.vertex.?.address.? });
        }

        if (self.mesh.buffers.index != null) {
            const index_copy = [_]vk.BufferCopy{.{
                .src_offset = self.vertice_bytes.len,
                .dst_offset = 0,
                .size = self.indice_bytes.len,
            }};
            self.ctx.device.cmdCopyBuffer(cmd, self.staging_buffer.vk_buffer, self.mesh.buffers.index.?.vk_buffer, &index_copy);
            log.info("Copy Mesh {} bytes of indices from offset {}", .{ self.indice_bytes.len, self.vertice_bytes.len });
        }
    }

    pub fn interface(self: *TransferBuffersCmd) CommandPool.GpuCommand {
        return CommandPool.GpuCommand.interface(self);
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
