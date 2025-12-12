const std = @import("std");
const System = @import("system.zig");
const ecs = @import("../ecs.zig");

const GameSystem = @This();

var allocator: std.mem.Allocator = undefined;
var is_initialised: bool = false;

pub fn init(
    // alloc: std.mem.Allocator
) GameSystem {
    // allocator = alloc;
    is_initialised = true;
    return .{};
}

pub fn system(self: *GameSystem) System {
    return System.init(self);
}

pub fn deinit(self: *GameSystem) void {
    _ = self;
}

pub fn setup(self: *GameSystem) void {
    _ = &self;
}

pub fn update(self: *GameSystem) void {
    _ = &self;
}
