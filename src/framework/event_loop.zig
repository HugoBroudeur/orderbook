const std = @import("std");
const log = std.log.scoped(.event_queue);
// Ring buffer implementation

const EventLoop = @This();

const MAX_PUSHED_EVENTS = 1024;

pub const EventType = enum {
    none,
    packet,
    mouse_move,
    mouse_pressed,
    keyboard_pressed,
};

pub const Event = struct {
    /// if time = .zero, will use current timestamp
    /// Clock is std.Io.Clock.cpu_process
    time: std.Io.Timestamp = .zero,
    type: EventType,
    value_1: u32,
    value_2: u32,

    /// bytes of data pointed to by ptr
    ptr_len: u32,
    ptr: ?*anyopaque,

    fn empty() Event {
        return .{
            .type = .none,
            .value_1 = 0,
            .value_2 = 0,
            .ptr_len = 0,
            .ptr = null,
        };
    }
};

allocator: std.mem.Allocator,
tail: u32 = 0,
head: u32 = 0,
pushed_events: [MAX_PUSHED_EVENTS]Event = undefined,

pub fn init(allocator: std.mem.Allocator) EventLoop {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *EventLoop) void {
    _ = self;
}

pub fn pushEvent(self: *EventLoop, ev: Event) void {
    const next_ev: *Event = undefined;

    next_ev = &self.pushed_events[self.head & (MAX_PUSHED_EVENTS - 1)];

    if (self.head - self.tail >= MAX_PUSHED_EVENTS) {
        log.warn("Queue overflow, attempting to enqueue {}", .{ev});
        // We are discarding an event but don't leak memory
        if (next_ev.ptr) |ptr| {
            self.allocator.free(ptr);
        }

        self.tail += 1;
    }

    if (ev.time == std.Io.Timestamp.zero) {
        const clock = std.Io.Clock.cpu_process;
        ev.time = std.Io.Timestamp.now(self.io, clock);
    }

    next_ev.* = ev;
    self.head += 1;
}

pub fn getEvent(self: *EventLoop) Event {
    if (self.head > self.tail) {
        self.tail += 1;
        return self.pushed_events[(self.tail - 1) & (MAX_PUSHED_EVENTS - 1)];
    }

    // TODO, return system event (SDL converted event)
    return Event.empty();
}

pub fn runEventLoop(self: *EventLoop) void {
    var ev = self.getEvent();

    while (ev.type != .none) {
        self.processEvent(ev);

        ev = self.getEvent();
    }
}

pub fn processEvent(self: *EventLoop, ev: Event) void {
    switch (ev.type) {
        .keyboard_pressed => {
            // TODO -> forward input system

        },
        else => {
            // TODO -> forward to event dispatcher
        },
    }

    // free any blocked data
    self.allocator.free(ev.ptr);
}
