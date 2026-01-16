// Interface definition for a layer, using Vtable
const std = @import("std");
const sdl = @import("sdl3");

const Event = @import("../events/event.zig");
// const Event = sdl.events.Event;

const Layer = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    onAttach: *const fn (*anyopaque) anyerror!void,
    onUpdate: *const fn (*anyopaque) void,
    onEvent: *const fn (*anyopaque, ev: Event) void,
    deinit: *const fn (*anyopaque) void,
};

pub fn onAttach(self: Layer) !void {
    return self.vtable.onAttach(self.ptr);
}
pub fn onUpdate(self: Layer) void {
    return self.vtable.onUpdate(self.ptr);
}
pub fn onEvent(self: Layer, ev: Event) void {
    return self.vtable.onEvent(self.ptr, ev);
}
pub fn deinit(self: Layer) void {
    return self.vtable.deinit(self.ptr);
}

pub fn init(ptr: anytype) Layer {
    const T = @TypeOf(ptr);
    const ptr_info = @typeInfo(T);
    const Impl = struct {
        fn onAttach(impl: *anyopaque) !void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.onAttach(self);
        }
        fn onUpdate(impl: *anyopaque) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.onUpdate(self);
        }
        fn onEvent(impl: *anyopaque, ev: Event) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.onEvent(self, ev);
        }
        fn deinit(impl: *anyopaque) void {
            const self: T = @ptrCast(@alignCast(impl));
            return ptr_info.pointer.child.deinit(self);
        }
    };

    return .{
        .ptr = ptr,
        .vtable = &.{
            .onAttach = Impl.onAttach,
            .onUpdate = Impl.onUpdate,
            .onEvent = Impl.onEvent,
            .deinit = Impl.deinit,
        },
    };
}
