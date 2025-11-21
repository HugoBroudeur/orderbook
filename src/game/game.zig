const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const slog = sokol.log;
const sapp = sokol.app;
// const use_docking = @import("build_options").docking;
const ig = @import("cimgui");
const tracy = @import("tracy");
// // const Delil = @import("gfx/delil_imgui.zig");
// const Delilv2 = @import("gfx/delil_v2.zig");
// const Delil = @import("gfx/delil.zig");
// const delil_pass = @import("gfx/render_pass.zig");
const Ecs = @import("ecs");
// const shape = @import("math/shape.zig");
// const logger = @import("debug/log.zig");

const simgui = sokol.imgui;

const Game = @This();

pub const GameError = error{
    ErrorInitialisation,
};

const game_allocator: std.mem.Allocator = undefined;
var ecs: Ecs = undefined;

const state = struct {
    var pass_action: sg.PassAction = .{};
    var show_first_window: bool = true;
    var show_second_window: bool = true;

    var window_width: u32 = 0;
    var window_height: u32 = 0;
    var is_demo_open = true;

    var progress: f32 = 0;
    var progress_dir: f32 = 1;
    var progress_bar_overlay: [32]u8 = undefined;

    var is_buy_button_clicked = false;
};

const FRAMES_PER_SECOND = 60.0;

// pub var gfx: Delilv2 = undefined;
// pub var pass: delil_pass.RenderPass = undefined;

var timing: Timing = .{
    .tick_acc = 0,
    .tick = 0,
    .fixed_framerate = .{
        .next_update_state = 0.0,
        .tick_frame = false,
    },
};

pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) void {
    tracy.frameMarkStart("Main");
    ecs = Ecs.init(allocator) catch |err| {
        std.log.err("[ERROR][game.init] Can't initiate : {}", .{err});
        shutdown();
        return;
    };

    state.window_width = width;
    state.window_height = height;

    // return .{
    //     .allocator = allocator,
    //     .ecs = ecs,
    // };
}

// delil: delil.Context = undefined,
pub fn setup() void {
    errdefer shutdown();
    // self.delil = delil.state;

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    sokol.time.setup();

    ecs.build_world() catch |err| {
        std.log.err("[ERROR][game.init] Can't build the world : {}", .{err});
        return;
    };

    // simgui.setup(.{
    //     .logger = .{ .func = slog.func },
    // });

    // try ecs.build_world();
    // if (!ecs.reg.singletons().has(data.RenderPass)) {
    //     std.log.err("[Game] Render Pass not initialised in the ECS", .{});
    //     return GameError.ErrorInitialisation;
    // }
    // var render_pass = ecs.reg.singletons().get(data.RenderPass);

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    // if (gfx.init()) {} else |err| {
    //     std.log.err("Can't initiate Delil: {}", .{err});
    //     shutdown();
    //     return;
    // }

    // ui.init();
}

pub fn frame() void {
    // const width = sapp.width();
    // const height = sapp.height();

    // Get current window size.
    // const ratio: f32 = @divExact(@as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)));
    // tracy.frameMark("yo yo");

    if (true) {
        ecs.progress();
        // const render_pass = ecs.reg.singletons().get(data.RenderPass);

        // sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
        // ecs.render(&state.pass_action);
        // simgui.render();
        // sg.endPass();
        // sg.commit();
    }
}

pub fn shutdown() void {
    ecs.deinit();
    // gfx.deinit();
    sg.shutdown();

    tracy.cleanExit();
}

pub fn handleEvent(ev: [*c]const sapp.Event) void {
    // var e = ev.*;

    ecs.collect(ev.*);
    // ecs.collectSokolEvent(e) catch unreachable; // TODO: improve, can fail memory allocation
    //
    // ecs.consumeEvent();
    // if (ev.*.type == .KEY_DOWN) {
    //     switch (ev.*.key_code) {
    //         // .ESCAPE => sapp.quit(),
    //         .D => logger.toggle(),
    //         .W => logger.toggleEcs(),
    //         else => {},
    //     }
    // }

    _ = simgui.handleEvent(ev.*);
}

const Timing = struct {
    tick_acc: u32 = 0,
    tick: u32 = 0,
    fixed_framerate: FixedFramerate,
};

const FixedFramerate = struct {
    const This = @This();
    next_update_state: f64 = 0.0,
    tick_frame: bool = false,

    pub fn shouldTick(self: *This, time: f64) bool {
        if (time > self.timing.next_update_state) {
            self.timing.next_update_state = time + (1.0 / FRAMES_PER_SECOND);
            self.timing.tick_frame = true;
            return true;
        } else {
            self.timing.tick_frame = false;
            return false;
        }
    }
};

pub fn timef() f32 {
    return @floatCast(sokol.time.sec(sokol.time.now()));
}

fn makeComboItems(comptime items: anytype) [*c]const u8 {
    comptime var buffer: []const u8 = "";

    inline for (items) |item| {
        buffer = buffer ++ item ++ "\x00";
    }

    buffer = buffer ++ "\x00";
    return buffer.ptr;
}
