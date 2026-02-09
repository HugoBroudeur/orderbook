// The CommandPool is a Vulkan implementation
const std = @import("std");
const log = std.log.scoped(.command_pool);
const assert = std.debug.assert;
const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");

const CommandPool = @This();

vk_cmd_pool: vk.CommandPool,

pub fn create(ctx: *const GraphicsContext) !CommandPool {
    const cpci: vk.CommandPoolCreateInfo = .{
        .queue_family_index = ctx.graphics_queue.family,
        .flags = .{ .reset_command_buffer_bit = true },
    };

    const vk_cmd_pool = try ctx.device.createCommandPool(&cpci, null);

    return .{ .vk_cmd_pool = vk_cmd_pool };
}

pub fn destroy(self: *CommandPool, ctx: *const GraphicsContext) void {
    ctx.device.destroyCommandPool(self.vk_cmd_pool, null);
}

// This pattern is not very efficient: we are waiting for the GPU command to fully execute before continuing with the CPU side logic.
// Recommended to run in seperate thread to load the data
pub fn immediateSubmit(self: *const CommandPool, ctx: *const GraphicsContext, queue_family: GraphicsContext.QueueFamily, cmds: []const GpuCommand) !void {
    const alloc_info = vk.CommandBufferAllocateInfo{
        .level = .primary,
        .command_pool = self.vk_cmd_pool,
        .command_buffer_count = 1,
    };

    var command_buffer: vk.CommandBuffer = undefined;
    try ctx.device.allocateCommandBuffers(&alloc_info, @ptrCast(&command_buffer));
    defer ctx.device.freeCommandBuffers(self.vk_cmd_pool, 1, @ptrCast(&command_buffer));

    const begin_info = vk.CommandBufferBeginInfo{
        .flags = .{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    };

    { // Issue commands
        try ctx.device.beginCommandBuffer(command_buffer, &begin_info);

        for (cmds) |cmd| {
            try cmd.execute(command_buffer);
        }

        try ctx.device.endCommandBuffer(command_buffer);
    }

    const submit_infos = [_]vk.SubmitInfo{.{
        .wait_semaphore_count = 0,
        .p_wait_semaphores = undefined,
        .p_wait_dst_stage_mask = undefined,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer),
        .signal_semaphore_count = 0,
        .p_signal_semaphores = undefined,
    }};

    try ctx.device.queueSubmit(queue_family.getQueue(ctx), submit_infos.len, &submit_infos, .null_handle);
    try ctx.device.queueWaitIdle(queue_family.getQueue(ctx));
}

pub const GpuCommand = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        execute: *const fn (*anyopaque, vk.CommandBuffer) anyerror!void,
    };

    pub fn execute(self: GpuCommand, cmdbuf: vk.CommandBuffer) !void {
        return self.vtable.execute(self.ptr, cmdbuf);
    }

    pub fn interface(ptr: anytype) GpuCommand {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn execute(impl: *anyopaque, cmdbuf: vk.CommandBuffer) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.execute(self, cmdbuf);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .execute = Impl.execute,
            },
        };
    }
};
