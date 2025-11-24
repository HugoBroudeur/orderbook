// Interface definition for a system, using Vtable
// const zecs = @import("zecs");
const std = @import("std");
const ecs = @import("../ecs.zig");

const System = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    // setup: *const fn (*anyopaque, reg: *zecs.Registry) void,
    // update: *const fn (*anyopaque, reg: *zecs.Registry) void,
    setup: *const fn (*anyopaque, world: *ecs.zflecs.world_t) void,
    update: *const fn (*anyopaque, world: *ecs.zflecs.world_t) void,
    deinit: *const fn (*anyopaque) void,
};

// pub fn setup(self: System, reg: *zecs.Registry) void {
//     return self.vtable.setup(self.ptr, reg);
// }
// pub fn update(self: System, reg: *zecs.Registry) void {
//     return self.vtable.update(self.ptr, reg);
// }
pub fn setup(self: System, world: *ecs.zflecs.world_t) void {
    return self.vtable.setup(self.ptr, world);
}
pub fn update(self: System, world: *ecs.zflecs.world_t) void {
    return self.vtable.update(self.ptr, world);
}
pub fn deinit(self: System) void {
    return self.vtable.deinit(self.ptr);
}

pub fn init(ptr: anytype) System {
    // const Impl = SystemDelegate(ptr);
    const T = @TypeOf(ptr);
    const ptr_info = @typeInfo(T);
    const Impl = struct {
        // fn setup(impl: *anyopaque, reg: *zecs.Registry) void {
        fn setup(impl: *anyopaque, world: *ecs.zflecs.world_t) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.setup(self, world);
        }
        // fn update(impl: *anyopaque, reg: *zecs.Registry) void {
        fn update(impl: *anyopaque, world: *ecs.zflecs.world_t) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.update(self, world);
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

// (5) Delegate to turn the opaque pointer back to the implementation.
// inline fn SystemDelegate(ptr: anytype) type {
//     const T = @TypeOf(ptr);
//     const ptr_info = @typeInfo(T);
//     return struct {
//         fn setup(impl: *anyopaque, reg: *zecs.Registry) void {
//             const self: T = @ptrCast(@alignCast(impl));
//             // const self: T = @fieldParentPtr(@ptrCast(@alignCast(impl)), "setup");
//             return ptr_info.pointer.child.setup(self, reg);
//         }
//         fn update(impl: *anyopaque, reg: *zecs.Registry) void {
//             const self: T = @ptrCast(@alignCast(impl));
//             return ptr_info.pointer.child.update(self, reg);
//         }
//         fn deinit(impl: *anyopaque) void {
//             const self: T = @ptrCast(@alignCast(impl));
//             return ptr_info.pointer.child.deinit(self);
//         }
//     };
// }
