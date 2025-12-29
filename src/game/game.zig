const std = @import("std");

const tracy = @import("tracy");
const Config = @import("../config.zig");
const DbManager = @import("db_manager.zig");
const RendererManager = @import("renderer_manager.zig");
const UiManager = @import("ui_manager.zig");
const EcsManager = @import("ecs_manager.zig");
const MarketManager = @import("market_manager.zig");
const FontManager = @import("font_manager.zig");
const UiSystem = @import("ecs/systems/ui_system.zig");

const sdl = @import("sdl3");
const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ifa = @import("fonticon");

const Game = @This();

const WINDOW_WIDTH = 1920;
const WINDOW_HEIGHT = 1060;
const WINDOW_TITLE = "Price is Power";
const IMGUI_HAS_DOCK = false;

pub const GameError = error{
    ErrorInitialisation,
};

const game_allocator: std.mem.Allocator = undefined;
var ecs_manager: EcsManager = undefined;
var db_manager: DbManager = undefined;
var renderer_manager: RendererManager = undefined;
var ui_manager: UiManager = undefined;
var market_manager: MarketManager = undefined;
var font_manager: FontManager = undefined;
var ui_system: UiSystem = undefined;

const FRAMES_PER_SECOND = 60.0;

var timing: Timing = .{
    .tick_acc = 0,
    .tick = 0,
    .fixed_framerate = .{
        .next_update_state = 0.0,
        .tick_frame = false,
    },
};

pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    errdefer shutdown();
    // tracy.frameMarkStart("Main");

    db_manager = DbManager.init(allocator, config) catch |err| {
        std.log.err("[Game][init] Can't initiate DbManager: {}", .{err});
        return err;
    };

    renderer_manager = RendererManager.init(allocator) catch |err| {
        std.log.err("[Game][init] Can't initiate RendererManager: {}", .{err});
        return err;
    };

    ui_system = UiSystem.init();
    font_manager = FontManager.init(allocator);
    ui_manager = UiManager.init(allocator, &db_manager, &ui_system, &font_manager);
    market_manager = MarketManager.init(allocator, &db_manager);
    ecs_manager = EcsManager.init(allocator, &db_manager, &renderer_manager, &ui_manager, &market_manager) catch |err| {
        std.log.err("[Game][init] Can't initiate EcsManager: {}", .{err});
        return err;
    };
}

pub fn setup() !void {
    errdefer shutdown();

    try renderer_manager.setup(&ecs_manager, WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT);
    try font_manager.setup();
    ecs_manager.setup(.{
        .gpu_target_info = RendererManager.createColorTargetInfo(),
        .gpu_pass = null,
        .clear_color = .{ .r = 0, .g = 0.5, .b = 1, .a = 1 },
    }) catch |err| {
        std.log.err("[Game][setup] Can't setup the EcsManager : {}", .{err});
        return err;
    };
    ui_manager.setup(&ecs_manager) catch |err| {
        std.log.err("[Game][setup] Can't setup the UiManager : {}", .{err});
        return err;
    };
    try market_manager.setup(&ecs_manager);
}

pub fn run() void {
    defer shutdown();

    setup() catch |err| {
        std.log.err("Error during Game Setup: {}", .{err});
        return;
    };

    var done = false;
    while (!done) {
        while (sdl.events.poll()) |event| {
            _ = impl_sdl3.ImGui_ImplSDL3_ProcessEvent(@ptrCast(&event.toSdl()));

            switch (event) {
                .quit => {
                    done = true;
                },
                .window_close_requested => {
                    if (event.getWindow()) |window| {
                        if (window.getId() catch 0 == renderer_manager.window.getId() catch 0) {
                            done = true;
                        }
                    }
                },
                .key_down => {
                    switch (event.key_down.key.?) {
                        .escape => {
                            done = true;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        ecs_manager.progress();
        ecs_manager.render();
    }
}

pub fn shutdown() void {
    db_manager.deinit();
    market_manager.deinit();
    ecs_manager.deinit();
    renderer_manager.deinit();
    ui_manager.deinit();
    font_manager.deinit();

    tracy.cleanExit();
}

// pub fn handleEvent(ev: [*c]const sapp.Event) void {
//     // var e = ev.*;
//
//     ecs.collect(ev.*);
//     // ecs.collectSokolEvent(e) catch unreachable; // TODO: improve, can fail memory allocation
//     //
//     // ecs.consumeEvent();
//     if (ev.*.type == .KEY_DOWN) {
//         switch (ev.*.key_code) {
//             .ESCAPE => sapp.quit(),
//             // .D => logger.toggle(),
//             // .W => logger.toggleEcs(),
//             else => {},
//         }
//     }
//
//     _ = simgui.handleEvent(ev.*);
// }

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
