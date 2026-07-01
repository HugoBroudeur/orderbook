const std = @import("std");

pub const Components = @import("components.zig");

pub const MB: usize = 1024 * 1000;
pub const Ecs = @import("knoedel").Knoedel(
    .{ .max_frame_mem = 128 * MB, .thread_count = 8 },
);

const World = @This();

const Schedule = enum {
    init,
    pre_update,
    update,
    post_update,
    pre_render,
    render,
    cleanup,
};

allocator: std.mem.Allocator,
io: std.Io,
app: *Ecs.App,

pub fn init(allocator: std.mem.Allocator, io: std.Io) !World {
    return .{
        .allocator = allocator,
        .io = io,
        .app = try Ecs.App.init(allocator, io),
    };
}

pub fn deinit(self: *World) void {
    self.app.deinit();
}
