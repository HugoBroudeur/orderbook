// Interface definition for a system, using Vtable
const std = @import("std");
const ecs = @import("../ecs.zig");

const System = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    setup: *const fn (*anyopaque) void,
    update: *const fn (*anyopaque) void,
    deinit: *const fn (*anyopaque) void,
};

pub fn setup(self: System) void {
    return self.vtable.setup(self.ptr);
}
pub fn update(self: System) void {
    return self.vtable.update(self.ptr);
}
pub fn deinit(self: System) void {
    return self.vtable.deinit(self.ptr);
}

pub fn init(ptr: anytype) System {
    const T = @TypeOf(ptr);
    const ptr_info = @typeInfo(T);
    const Impl = struct {
        fn setup(impl: *anyopaque) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.setup(self);
        }
        fn update(impl: *anyopaque) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.update(self);
        }
        fn deinit(impl: *anyopaque) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.deinit(self);
        }
    };

    return .{
        .ptr = ptr,
        .vtable = &.{
            .setup = Impl.setup,
            .update = Impl.update,
            .deinit = Impl.deinit,
        },
    };
}
