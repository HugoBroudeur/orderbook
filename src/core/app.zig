const std = @import("std");
const assert = std.debug.assert;

const tracy = @import("tracy");
const Config = @import("../config.zig");
const Colors = @import("../game/colors.zig");

const sdl = @import("sdl3");
const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ifa = @import("fonticon");

const Layer = @import("layer.zig");
const LayerStack = @import("layer_stack.zig");
const Framerate = @import("framerate.zig");
const SandboxLayer = @import("../layers/sandbox.zig");
const Window = @import("window.zig");
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
const FPS_THREASHOLD: u32 = 140;
const FPS_LIMITER: bool = false;
const V_SYNC: bool = true;
const IMGUI_HAS_DOCK = false;
const SDL_INIT_FLAGS: sdl.InitFlags = .{ .video = true, .gamepad = true, .audio = true };

//
// Global state
//

var window: Window = undefined;
var running = true;
var framerate = Framerate.Fixed.init(FPS_THREASHOLD);
var layer_stack: LayerStack.LayerStack(MAX_LAYERS, MAX_OVERLAYS) = undefined;
var sandbox_layer: SandboxLayer = undefined;

pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    errdefer shutdown();
    // tracy.frameMarkStart("Main");

    try initSdlBackend();

    window = Window.create(.{}) catch |err| {
        std.log.err("[App] Can't create the Window : {}", .{err});
        return err;
    };
    try window.setIcon("assets/favicon.ico");
    window.setVSync(V_SYNC);

    sandbox_layer = SandboxLayer.init("Sandbox layer", allocator, config, &window, &framerate);
    layer_stack = try LayerStack.LayerStack(MAX_LAYERS, MAX_OVERLAYS).init();

    try pushLayer(sandbox_layer.interface());
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
        _ = impl_sdl3.ImGui_ImplSDL3_ProcessEvent(@ptrCast(&event.toSdl()));
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
    for (layer_stack.stack()) |layer| {
        layer.deinit();
    }
    window.deinit();

    sdl.quit(SDL_INIT_FLAGS);

    std.log.info("[App] Closing... Good Bye!", .{});
    tracy.cleanExit();
}

pub fn pushLayer(layer: Layer) !void {
    layer_stack.pushLayer(layer);
    try layer.onAttach();
}

pub fn pushOverlay(layer: Layer) !void {
    layer_stack.pushOverlay(layer);
    try layer.onAttach();
}
