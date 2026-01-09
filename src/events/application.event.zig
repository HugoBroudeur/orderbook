const Event = @import("event.zig");

pub const ApplicationEvent = Event.CategoryEvent(.application);
//     window_closed: WindowClosedEvent,
//     window_open: WindowClosedEvent,
// };

pub const WindowClosedEvent = struct {
    pub fn toString() []const u8 {
        return "WindowClosedEvent";
    }
};
