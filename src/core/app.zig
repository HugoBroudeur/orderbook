const std = @import("std");
const assert = std.debug.assert;

const tracy = @import("tracy");
const Config = @import("../config.zig");
const Colors = @import("../game/colors.zig");

const sdl = @import("sdl3");
// const impl_sdl3 = @import("impl_sdl3");
// const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ifa = @import("fonticon");

const Layer = @import("layer.zig");
const LayerStack = @import("layer_stack.zig");
const Framerate = @import("framerate.zig");
const SandboxLayer = @import("../layers/sandbox.zig");
const Window = @import("window.zig");
const Display = @import("display.zig");
const Event = @import("../events/event.zig");

const App = @This();

//
// Config
//
const MAX_LAYERS = 1;
const MAX_OVERLAYS = 0;

const WINDOW_WIDTH = 1920;
const WINDOW_HEIGHT = 1060;
const WINDOW_TITLE = "Price is Power";
const FPS_THREASHOLD: u32 = 165;
const FPS_LIMITER: bool = true;
const V_SYNC: bool = false;
const IMGUI_HAS_DOCK = false;
const SDL_INIT_FLAGS: sdl.InitFlags = .{ .video = true, .gamepad = true, .audio = true };

//
// Global state
//

var has_booted: bool = false;
var display: Display = undefined;
var window: Window = undefined;
var running = true;
var framerate: Framerate.Fixed = undefined;
var layer_stack: LayerStack.LayerStack(MAX_LAYERS, MAX_OVERLAYS) = undefined;
var sandbox_layer: SandboxLayer = undefined;

pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    errdefer shutdown();
    // tracy.frameMarkStart("Main");

    try initSdlBackend();

    display = try .init();
    window = Window.create(.{}) catch |err| {
        std.log.err("[App] Can't create the Window : {}", .{err});
        return err;
    };
    display.detectCurrentDisplay(&window);
    window.center(display);
    try window.setIcon("assets/favicon.ico");
    // window.setVSync(V_SYNC);
    framerate = Framerate.Fixed.init(@intFromFloat(display.refresh_rate));

    sandbox_layer = SandboxLayer.init(allocator, config, &window, &framerate);
    layer_stack = try LayerStack.LayerStack(MAX_LAYERS, MAX_OVERLAYS).init();

    try pushLayer(sandbox_layer.interface());
    has_booted = true;
}

pub fn run() void {
    defer shutdown();

    if (FPS_LIMITER) {
        framerate.on();
    } else {
        framerate.off();
    }

    while (running) {
        pollEvent();

        for (layer_stack.stack()) |layer| {
            layer.onUpdate();
        }

        if (framerate.skipDrawThreasholdReached()) {
            std.log.err("[App.run] PREVENTING FRAME LAG, EXITING NOW", .{});
            return;
        }
    }
}

pub fn pollEvent() void {
    while (sdl.events.poll()) |event| {
        // _ = impl_sdl3.ImGui_ImplSDL3_ProcessEvent(@ptrCast(&event.toSdl()));
        const ev = Event.create(event);

        for (layer_stack.stack()) |layer| {
            layer.onEvent(ev);
        }

        switch (event) {
            .quit => {
                running = false;
            },
            .window_close_requested => {
                if (event.getWindow()) |w| {
                    if (w.getId() catch 0 == window.ptr.getId() catch 0) {
                        running = false;
                    }
                }
            },
            .window_display_changed => {
                display.detectCurrentDisplay(&window);
                framerate.setTargetFps(@intFromFloat(display.refresh_rate));
            },
            else => {},
        }
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
    if (has_booted) {
        for (layer_stack.stack()) |layer| {
            layer.deinit();
        }
    }
    window.deinit();

    sdl.quit(SDL_INIT_FLAGS);

    std.log.info("[App] Closing... Good Bye!", .{});
    tracy.cleanExit();
}

pub fn pushLayer(layer: Layer) !void {
    layer_stack.pushLayer(layer);
    layer.onAttach() catch |err| {
        std.log.err("[App] Error while attaching layer {s}. {}", .{ layer.getLabel(), err });
        return err;
    };
}

pub fn pushOverlay(layer: Layer) !void {
    layer_stack.pushOverlay(layer);
    layer.onAttach() catch |err| {
        std.log.err("[App] Error while attaching layer {s}. {}", .{ layer.getLabel(), err });
        return err;
    };
}
