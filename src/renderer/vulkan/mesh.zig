// The mesh assume indice u16,

const std = @import("std");
const log = std.log.scoped(.mesh);
const assert = std.debug.assert;
const vk = @import("vulkan");
const sdl = @import("sdl3");
const zm = @import("zmath");

const Renderer = @import("renderer_2d.zig");
const Buffer = @import("buffer.zig");
const CommandPool = @import("command_pool.zig");
const Image = @import("image.zig");
const Data = @import("../data.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");

const Mesh = @This();

pub const MeshBuffers = struct {
    index: ?Buffer = null,
    vertex: ?Buffer = null,
    // storage: ?Buffer = null,
};

pub const GeoSurface = struct {
    start_index: u32 = 0,
    count: u32 = 0,
};

pub const PushConstants2D = struct {
    scale: Data.Scale2D,
    translate: Data.Translate2D,
    vb_address: vk.DeviceAddress = undefined,
};

pub const PushConstants3D = struct {
    world_matrix: Data.WorldMatrix3D,
    vb_address: vk.DeviceAddress = undefined,
};
pub const PushConstantType = enum { two_d, three_d };

pub const PushConstants = union(PushConstantType) {
    two_d: PushConstants2D,
    three_d: PushConstants3D,
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
    ctx: *const GraphicsContext,
    cmd_pool: *const CommandPool,
    vertices: []const Data.Vertex,
    indices: []const Data.Indice,
) !void {
    const vertice_bytes = std.mem.sliceAsBytes(vertices);
    const indice_bytes = std.mem.sliceAsBytes(indices);

    try self.setVerticeBuffer(ctx, @intCast(vertice_bytes.len));
    try self.setIndiceBuffer(ctx, @intCast(indice_bytes.len));

    var cmd = try TransferBuffersCmd.create(self, ctx, vertice_bytes, indice_bytes);
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
    vertices: [4]Data.Quad.Vertex,
    indices: []const Data.Quad.Indice,
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
pub fn makeTriangleMesh(allocator: std.mem.Allocator, ctx: *const GraphicsContext, cmd_pool: *const CommandPool, vertices: [3]Data.Quad.Vertex) !Mesh {
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
            self.ctx.device.cmdCopyBuffer(cmd, self.staging_buffer.vk_buffer, self.mesh.buffers.vertex.?.vk_buffer, vertex_copy.len, &vertex_copy);

            log.info("Copy Mesh {} bytes of vertices into VB addr {}", .{ self.vertice_bytes.len, self.mesh.buffers.vertex.?.address.? });
        }

        if (self.mesh.buffers.index != null) {
            const index_copy = [_]vk.BufferCopy{.{
                .src_offset = self.vertice_bytes.len,
                .dst_offset = 0,
                .size = self.indice_bytes.len,
            }};
            self.ctx.device.cmdCopyBuffer(cmd, self.staging_buffer.vk_buffer, self.mesh.buffers.index.?.vk_buffer, index_copy.len, &index_copy);
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

// TODO, so much issue with Zig test having aligment/can't load file
// test "make quad mesh" {
//     // const allocator = std.testing.allocator;
//     // var gpa = std.heap.DebugAllocator(.{
//     //     .safety = true, // Enable safety checks
//     //     // .thread_safe = true, // Thread safety
//     //     .verbose_log = true, // Set true for detailed logs
//     // }){};
//     // defer {
//     //     const leaked = gpa.deinit();
//     //     if (leaked == .leak) {
//     //         std.debug.print("MEMORY LEAK DETECTED!\n", .{});
//     //     }
//     // }
//     // const allocator = gpa.allocator();
//
//     var threadsafe = std.heap.ThreadSafeAllocator{ .child_allocator = std.testing.allocator };
//     const allocator = threadsafe.allocator();
//
//     var ctx = try GraphicsContext.init(allocator);
//     defer ctx.deinit();
//     var renderer = try Renderer.init(allocator, &ctx);
//     const vertices = Data.quad_vertices;
//     const indices = &Data.quad_indices;
//     try renderer.setup();
//     defer renderer.deinit();
//     const cmd_pool = &renderer.getCurrentFrame().cmd_pool;
//
//     const mesh = try makeQuadMesh(allocator, &ctx, cmd_pool, vertices, indices);
//
//     const indice_bytes = std.mem.sliceAsBytes(indices);
//
//     try std.testing.expectEqual(indice_bytes.len, 6 * 2); // 6 indices of u16 (2 bytes)
//
//     // READBACK TEST: Create a readback buffer and verify index data
//     var readback_buffer = try Buffer.create(
//         &ctx,
//         @intCast(indice_bytes.len),
//         .{ .transfer_dst_bit = true },
//         .{ .host_visible_bit = true, .host_coherent_bit = true },
//     );
//     defer readback_buffer.destroy(&ctx);
//
//     // Copy index buffer to readback buffer
//     const alloc_info = vk.CommandBufferAllocateInfo{
//         .level = .primary,
//         .command_pool = cmd_pool.vk_cmd_pool,
//         .command_buffer_count = 1,
//     };
//     var command_buffer: vk.CommandBuffer = undefined;
//     try ctx.device.allocateCommandBuffers(&alloc_info, @ptrCast(&command_buffer));
//     defer ctx.device.freeCommandBuffers(cmd_pool.vk_cmd_pool, 1, @ptrCast(&command_buffer));
//
//     try ctx.device.beginCommandBuffer(command_buffer, &.{ .flags = .{ .one_time_submit_bit = true } });
//     const copy_region = vk.BufferCopy{ .src_offset = 0, .dst_offset = 0, .size = indice_bytes.len };
//     ctx.device.cmdCopyBuffer(command_buffer, mesh.buffers.index.?.vk_buffer, readback_buffer.vk_buffer, 1, @ptrCast(&copy_region));
//     try ctx.device.endCommandBuffer(command_buffer);
//
//     const submit_info = vk.SubmitInfo{
//         .command_buffer_count = 1,
//         .p_command_buffers = @ptrCast(&command_buffer),
//         .wait_semaphore_count = 0,
//         .p_wait_semaphores = undefined,
//         .p_wait_dst_stage_mask = undefined,
//         .signal_semaphore_count = 0,
//         .p_signal_semaphores = undefined,
//     };
//     try ctx.device.queueSubmit(ctx.graphics_queue.handle, 1, @ptrCast(&submit_info), .null_handle);
//     try ctx.device.queueWaitIdle(ctx.graphics_queue.handle);
//
//     const data = try ctx.device.mapMemory(readback_buffer.memory, 0, vk.WHOLE_SIZE, .{});
//     defer ctx.device.unmapMemory(readback_buffer.memory);
//     const readback_indices = @as([*]const u8, @ptrCast(data))[0..indice_bytes.len];
//     try std.testing.expectEqual(indice_bytes, readback_indices);
// }
