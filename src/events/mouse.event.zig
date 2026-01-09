const Event = @import("event.zig");

pub const MouseEvent = union(Event.CategoryEvent(.mouse)) {
    mouse_moved: MouseMovedEvent,
};

pub const MouseMovedEvent = struct {
    x: u32,
    y: u32,

    pub fn toString() []const u8 {
        return "MouseMovedEvent";
    }
};
