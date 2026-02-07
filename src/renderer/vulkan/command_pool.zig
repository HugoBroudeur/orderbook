// The CommandPool is a Vulkan implementation
const std = @import("std");
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
