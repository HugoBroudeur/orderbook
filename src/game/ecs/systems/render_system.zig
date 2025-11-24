// Interface definition for a system, using Vtable
// const zecs = @import("zecs");
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const ecs = @import("../ecs.zig");

const RenderSystem = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    setup: *const fn (*anyopaque) void,
    render: *const fn (*anyopaque, world: *ecs.zflecs.world_t, pass_action: *sg.PassAction) void,
    deinit: *const fn (*anyopaque) void,
};

pub fn setup(self: RenderSystem) void {
    return self.vtable.setup(self.ptr);
}
pub fn render(self: RenderSystem, world: *ecs.zflecs.world_t, pass_action: *sg.PassAction) void {
    return self.vtable.render(self.ptr, world, pass_action);
}
pub fn deinit(self: RenderSystem) void {
    return self.vtable.deinit(self.ptr);
}

pub fn init(ptr: anytype) RenderSystem {
    const T = @TypeOf(ptr);
    const ptr_info = @typeInfo(T);

    const Impl = struct {
        pub fn setup(impl: *anyopaque) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.setup(self);
        }
        pub fn render(impl: *anyopaque, world: *ecs.zflecs.world_t, pass_action: *sg.PassAction) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.render(self, world, pass_action);
        }
        pub fn deinit(impl: *anyopaque) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.deinit(self);
        }
    };

    return .{
        .ptr = ptr,
        .vtable = &.{
            .setup = Impl.setup,
            .render = Impl.render,
            .deinit = Impl.deinit,
        },
    };
}
