const std = @import("std");

pub const Components = @import("components.zig");
pub const Systems = @import("systems.zig");

pub const MB: usize = 1024 * 1000;
pub const Ecs = @import("knoedel").Knoedel(
    .{ .max_frame_mem = 128 * MB, .thread_count = 8 },
);

const World = @This();

pub const Schedule = enum {
    /// Use in Game Layer
    pre_update,
    /// Use in Game Layer
    update,
    /// Use in Game Layer
    post_update,

    /// Use in Render Layer
    pre_render,
    /// Use in Render Layer
    render,

    /// Use in App
    cleanup,
};

pub const Gamestate = enum {
    boot,
    loading,
    menu,
    main,
    shutdown,
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
    if (self.app.getResource(World.Ecs.State(World.Gamestate)) catch null) |state| {
        state.set(.shutdown);

        self.app.runPar(World.Schedule.cleanup);
        self.app.flushCommands();
    }

    self.app.deinit();
}
