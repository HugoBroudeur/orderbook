// The CommandPool is a Vulkan implementation
const std = @import("std");
const log = std.log.scoped(.command_pool);
const assert = std.debug.assert;
const vk = @import("vulkan");

const Engine = @import("engine.zig");

const CommandPool = @This();

vk_cmd_pool: vk.CommandPool,

pub fn create(engine: *Engine) !CommandPool {
    const cpci: vk.CommandPoolCreateInfo = .{
        .queue_family_index = engine.ctx.graphics_queue.family,
        .flags = .{ .reset_command_buffer_bit = true },
    };

    const vk_cmd_pool = try engine.ctx.device.createCommandPool(&cpci, null);

    return .{ .vk_cmd_pool = vk_cmd_pool };
}

pub fn destroy(self: *CommandPool, engine: *Engine) void {
    engine.ctx.device.destroyCommandPool(self.vk_cmd_pool, null);
}

pub const GpuCommand = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        execute: *const fn (*anyopaque, *Engine) anyerror!void,
    };

    pub fn execute(self: GpuCommand, engine: *Engine) !void {
        return self.vtable.execute(self.ptr, engine);
    }

    pub fn interface(ptr: anytype) GpuCommand {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn execute(impl: *anyopaque, engine: *Engine) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.execute(self, engine);
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
