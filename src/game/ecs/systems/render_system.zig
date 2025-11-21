// Interface definition for a system, using Vtable
// const zecs = @import("zecs");
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const f = @import("zflecs");

const RenderSystem = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    setup: *const fn (*anyopaque, world: *f.world_t) void,
    render: *const fn (*anyopaque, world: *f.world_t, pass_action: *sg.PassAction) void,
    deinit: *const fn (*anyopaque) void,
};

pub fn setup(self: RenderSystem, world: *f.world_t) void {
    return self.vtable.setup(self.ptr, world);
}
pub fn render(self: RenderSystem, world: *f.world_t, pass_action: *sg.PassAction) void {
    return self.vtable.render(self.ptr, world, pass_action);
}
pub fn deinit(self: RenderSystem) void {
    return self.vtable.deinit(self.ptr);
}

pub fn init(ptr: anytype) RenderSystem {
    const T = @TypeOf(ptr);
    const ptr_info = @typeInfo(T);

    const Impl = struct {
        pub fn setup(impl: *anyopaque, world: *f.world_t) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.setup(self, world);
        }
        pub fn render(impl: *anyopaque, world: *f.world_t, pass_action: *sg.PassAction) void {
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
