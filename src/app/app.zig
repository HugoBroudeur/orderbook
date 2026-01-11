const std = @import("std");
const assert = std.debug.assert;

const tracy = @import("tracy");
const Config = @import("../config.zig");
const Colors = @import("../game/colors.zig");
const DbManager = @import("../game/db_manager.zig");
const RendererManager = @import("../game/renderer_manager.zig");
const Renderer2D = @import("../renderer/renderer_2d.zig");
const UiManager = @import("../game/ui_manager.zig");
const EcsManager = @import("../game/ecs_manager.zig");
const MarketManager = @import("../game/market_manager.zig");
const FontManager = @import("../game/font_manager.zig");
const PipelineManager = @import("../game/pipeline_manager.zig");
const ClayManager = @import("../game/clay_manager.zig");
const DrawApi = @import("../game/draw_api.zig");
const UiSystem = @import("../game/ecs/systems/ui_system.zig");

const sdl = @import("sdl3");
const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ifa = @import("fonticon");

const Layer = @import("layer.zig");
const LayerStack = @import("layer_stack.zig");
const Window = @import("window.zig");
const Event = @import("../events/event.zig");

const App = @This();

const WINDOW_WIDTH = 1920;
const WINDOW_HEIGHT = 1060;
const WINDOW_TITLE = "Price is Power";
const IMGUI_HAS_DOCK = false;
const SDL_INIT_FLAGS: sdl.InitFlags = .{ .video = true, .gamepad = true, .audio = true };

var running = true;

pub const GameError = error{
    ErrorInitialisation,
};

const game_allocator: std.mem.Allocator = undefined;

var window: Window = undefined;

var ecs_manager: EcsManager = undefined;
var db_manager: DbManager = undefined;
var renderer_2d: Renderer2D = undefined;
var renderer_manager: RendererManager = undefined;
var ui_manager: UiManager = undefined;
var market_manager: MarketManager = undefined;
var font_manager: FontManager = undefined;
var clay_manager: ClayManager = undefined;
var pipeline_manager: PipelineManager = undefined;
// var draw_api: DrawApi = undefined;
var ui_system: UiSystem = undefined;

pub const FPS_THREASHOLD: u32 = 80;

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

    renderer_2d = Renderer2D.init(allocator) catch |err| {
        std.log.err("[Game][init] Can't initiate Renderer2D: {}", .{err});
        return err;
    };

    // const la

    ui_system = UiSystem.init();
    font_manager = FontManager.init(allocator);
    ui_manager = UiManager.init(allocator, &db_manager, &ui_system, &font_manager);
    market_manager = MarketManager.init(allocator, &db_manager);
    // draw_api = DrawApi.init(&renderer_2d.gpu);
    // clay_manager = try ClayManager.init(allocator, &font_manager, &draw_api);
    clay_manager = try ClayManager.init(allocator, &font_manager);
    ecs_manager = EcsManager.init(allocator, &db_manager, &renderer_2d, &ui_manager, &market_manager) catch |err| {
        std.log.err("[Game][init] Can't initiate EcsManager: {}", .{err});
        return err;
    };
}

pub fn setup() !void {
    window = Window.create(.{}) catch |err| {
        std.log.err("[App] Can't create the Window : {}", .{err});
        return err;
    };
    try window.setIcon("assets/favicon.ico");
    window.setVSync(true);
    window.setEventCallback(onEvent);

    renderer_2d.setup(
        &window,
        &font_manager,
        &clay_manager,
    ) catch |err| {
        std.log.err("[App] Can't setup the 2D Renderer : {}", .{err});
        return err;
    };
    font_manager.setup() catch |err| {
        std.log.err("[App] Can't setup the FontManager : {}", .{err});
        return err;
    };

    ecs_manager.setup(.{ .clear_color = Colors.Teal }) catch |err| {
        std.log.err("[App] Can't setup the EcsManager : {}", .{err});
        return err;
    };
    ui_manager.setup(&ecs_manager) catch |err| {
        std.log.err("[App] Can't setup the UiManager : {}", .{err});
        return err;
    };
    clay_manager.setup() catch |err| {
        std.log.err("[App] Can't setup the ClayManager : {}", .{err});
        return err;
    };
    market_manager.setup(&ecs_manager) catch |err| {
        std.log.err("[App] Can't setup the MarketManager : {}", .{err});
        return err;
    };
}

pub fn run() void {
    defer shutdown();

    setup() catch |err| {
        std.log.err("[App] Error during Game Setup: {}", .{err});
        return;
    };

    var framerate = FixedFramerate.init(FPS_THREASHOLD);

    while (running) {
        pollEvent();

        framerate.update_count = 0;
        while (framerate.shouldWait()) {}

        while (framerate.shouldUpdate()) {
            ecs_manager.progress();
        }
        assert(framerate.update_count > 0); // Make sure at least 1 update happened

        // if (framerate.shouldDraw()) {
        ecs_manager.render();
        // }
    }
}

pub fn pollEvent() void {
    while (sdl.events.poll()) |event| {
        _ = impl_sdl3.ImGui_ImplSDL3_ProcessEvent(@ptrCast(&event.toSdl()));
        var ev = Event.create(event);
        onEvent(&ev);
    }
}

pub fn onEvent(event: *Event) void {
    // std.log.info("[App.onEvent] {}", .{event.getEventType()});

    // var dispatcher = Event.Dispatcher.init(event);

    // dispatcher.dispatch(Event.Application.ApplicationEvent, onWindowClose);

    // dispatcher.dispatch(
    //     u32,
    // );

    // if (event.scoped(.keyboard)) |ev| {
    //     Event.performKeyboardEvent(ev);
    // }
    switch (event.ptr) {
        .quit => {
            running = false;
        },
        .window_close_requested => {
            if (event.ptr.getWindow()) |w| {
                if (w.getId() catch 0 == window.ptr.getId() catch 0) {
                    running = false;
                }
            }
        },
        .key_down => {
            switch (event.ptr.key_down.key.?) {
                .escape => {
                    running = false;
                },
                else => {},
            }
        },
        else => {},
    }
}

pub fn initSdlBackend() !void {
    sdl.init(SDL_INIT_FLAGS) catch |err| {
        std.log.err("Error: {?s}", .{sdl.errors.get()});
        return err;
    };

    sdl.log.setAllPriorities(.debug);
}

pub fn shutdown() void {
    db_manager.deinit();
    market_manager.deinit();
    ecs_manager.deinit();
    renderer_2d.deinit();
    renderer_manager.deinit();
    ui_manager.deinit();
    font_manager.deinit();
    clay_manager.deinit();
    // draw_api.deinit();
    window.deinit();

    sdl.quit(SDL_INIT_FLAGS);

    std.log.info("[App] Closing... Good Bye!", .{});
    tracy.cleanExit();
}

pub fn onWindowClose(e: *Event.Application.WindowClosedEvent) bool {
    _ = e;
    running = false;

    return true;
}

const Timing = struct {
    tick_acc: u32 = 0,
    tick: u32 = 0,
    fixed_framerate: FixedFramerate,
};

// SDL implementation
const FixedFramerate = struct {
    const This = @This();

    pub const ONE_MILLISECOND = 1_000_000;
    pub const ONE_NANOSECOND = 1_000_000_000;

    // Calculated on start
    freq: u64,
    max_accumulated: u64,
    threshold: u64,

    // Tick value
    accumulated: u64 = 0,
    last_tick: u64,

    // Measure time passing
    dt: f32 = 0,
    seconds: f32 = 0,
    seconds_real: f32 = 0,

    // Frame Management
    update_count: u32 = 0,
    frame_lag: u32 = 0,
    running_slow: bool = false,

    pub fn init(fps: u32) FixedFramerate {
        const freq = sdl.timer.getPerformanceFrequency();
        return .{
            .freq = freq,
            .max_accumulated = @intCast(freq / 2),
            .threshold = freq / @as(u64, fps),
            .last_tick = sdl.timer.getPerformanceCounter(),
        };
    }

    pub fn shouldWait(self: *This) bool {
        const pc = sdl.timer.getPerformanceCounter();
        self.accumulated += pc - self.last_tick;
        self.last_tick = pc;

        if (self.accumulated > self.threshold) {
            if (self.accumulated > self.max_accumulated) {
                self.accumulated = self.max_accumulated;
            }

            return false;
        }

        const remaining_ns: u64 = ((self.threshold - self.accumulated) * ONE_NANOSECOND) / self.freq;
        if (remaining_ns > ONE_MILLISECOND) { // sleep if remaining > 1ms
            sdl.timer.delayNanoseconds(remaining_ns);
        }

        return true;
    }

    pub fn shouldUpdate(self: *This) bool {
        if (self.accumulated >= self.threshold) {
            const dt = self.getDtSinceLastFrame();
            self.accumulated -= self.threshold;
            self.dt = dt;
            self.seconds += self.dt;
            self.seconds_real += self.dt;
            self.update_count += 1;
            return true;
        }

        return false;
    }

    pub fn shouldDraw(self: *This) bool {
        self.frame_lag += @max(0, self.update_count - 1);
        const dt = self.getDtSinceLastFrame();
        if (self.running_slow) {
            if (self.frame_lag == 0) {
                self.running_slow = false;
            } else if (self.frame_lag > 10) {
                // Supress rendering, give `update` chance to catch up
                return false;
            }
        } else if (self.frame_lag >= 5) {
            // Consider game running slow when lagging more than 5 frames
            self.running_slow = true;
        }
        if (self.frame_lag > 0 and self.update_count == 1) self.frame_lag -= 1;

        // Set delta time between `draw`
        self.dt = @as(f32, @floatFromInt(self.update_count)) * dt;

        return true;
    }

    pub fn getDtSinceLastFrame(self: *FixedFramerate) f32 {
        return @floatCast(
            @as(f64, @floatFromInt(self.threshold)) / @as(f64, @floatFromInt(self.freq)),
        );
    }
};
