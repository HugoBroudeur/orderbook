// The CommandPool is a Vulkan implementation
const std = @import("std");
const log = std.log.scoped(.command_pool);
const assert = std.debug.assert;
const vk = @import("vulkan");

const Engine = @import("engine.zig");

pub const AllocatedCommandBuffer = struct {
    vk_command_buffer: vk.CommandBuffer,

    pub fn allocate(engine: *Engine, pool: CommandPool) !AllocatedCommandBuffer {
        var allocated_command_buffer: AllocatedCommandBuffer = .{
            .vk_command_buffer = undefined,
        };

        try engine.ctx.device.allocateCommandBuffers(&.{
            .command_pool = pool.vk_cmd_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&allocated_command_buffer.vk_command_buffer));

        return allocated_command_buffer;
    }

    pub fn destroy(self: *AllocatedCommandBuffer, engine: *Engine) void {
        engine.ctx.device.freeCommandBuffers(engine.getCurrentFrame().cmd_pool.vk_cmd_pool, &.{self.vk_command_buffer});
    }
};

pub const ImmediateCommands = struct {
    commands: std.ArrayList(GpuCommand),
    buffer: AllocatedCommandBuffer,

    pub fn init(engine: *Engine, pool: CommandPool) !ImmediateCommands {
        return .{
            .commands = .empty,
            .buffer = try AllocatedCommandBuffer.allocate(engine, pool),
        };
    }

    pub fn deinit(self: *ImmediateCommands, engine: *Engine) void {
        self.commands.deinit(engine.allocator);
        self.buffer.destroy(engine);
    }

    pub fn addCommand(self: *ImmediateCommands, allocator: std.mem.Allocator, cmd: GpuCommand) !void {
        try self.commands.append(allocator, cmd);
    }
};

pub const CommandPool = struct {
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
};

pub const GpuCommand = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        execute: *const fn (*anyopaque, *Engine) anyerror!void,
    };

    pub fn execute(self: GpuCommand, engine: *Engine) !void {
        return self.vtable.execute(self.ptr, engine);
    }
    pub fn getCommandBuffer(self: GpuCommand) vk.CommandBuffer {
        return self.vtable.getCommandBuffer(self.ptr);
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
