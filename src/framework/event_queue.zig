const std = @import("std");
const sdl = @import("sdl3");
const log = std.log.scoped(.event_queue);
// Ring buffer implementation

const EventQueue = @This();

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
    type: EventType = .none,

    ptr: ?sdl.events.Event,

    fn empty() Event {
        return .{
            .type = .none,
            .ptr = null,
        };
    }
};

allocator: std.mem.Allocator,
io: std.Io,
tail: u32 = 0,
head: u32 = 0,
pushed_events: [MAX_PUSHED_EVENTS]Event = undefined,

pub fn init(allocator: std.mem.Allocator, io: std.Io) EventQueue {
    return .{
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *EventQueue, allocator: std.mem.Allocator) void {
    _ = self;
    _ = allocator;
}

pub fn pushEvent(self: *EventQueue, ev: *Event) void {
    var next_ev: *Event = undefined;

    next_ev = &self.pushed_events[self.head & (MAX_PUSHED_EVENTS - 1)];

    if (self.head - self.tail >= MAX_PUSHED_EVENTS) {
        log.warn("Queue overflow, discarding oldest event", .{});
        self.tail += 1;
    }

    if (ev.time.toNanoseconds() == std.Io.Timestamp.zero.toNanoseconds()) {
        const clock = std.Io.Clock.cpu_process;
        ev.time = std.Io.Timestamp.now(self.io, clock);
    }

    next_ev.* = ev.*;
    self.head += 1;
}

pub fn getEvent(self: *EventQueue) ?Event {
    if (self.head > self.tail) {
        self.tail += 1;
        return self.pushed_events[(self.tail - 1) & (MAX_PUSHED_EVENTS - 1)];
    }

    // TODO, return system event (SDL converted event)
    return null;
}

pub fn runEventLoop(self: *EventQueue) void {
    var ev = self.getEvent();

    while (ev.type != .none) {
        self.processEvent(ev);

        ev = self.getEvent();
    }
}

pub fn processEvent(self: *EventQueue, ev: Event) void {
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
