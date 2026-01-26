const std = @import("std");
const assert = std.debug.assert;

const tracy = @import("tracy");
const Config = @import("../config.zig");
const Colors = @import("../game/colors.zig");

const sdl = @import("sdl3");
// const impl_sdl3 = @import("impl_sdl3");
// const impl_sdlgpu3 = @import("impl_sdlgpu3");

const Layer = @import("layer.zig");
const LayerStack = @import("layer_stack.zig");
const Framerate = @import("framerate.zig");
const SandboxSdlLayer = @import("../layers/sandbox_sdl.zig");
const SandboxVulkanLayer = @import("../layers/sandbox_vulkan.zig");
const GraphicsContext = @import("graphics_context.zig");
const Event = @import("../events/event.zig");

const App = @This();

//
// Config
//
const MAX_LAYERS = 1;
const MAX_OVERLAYS = 0;

const FPS_THREASHOLD: u32 = 165;
const FPS_LIMITER: bool = true;

//
// Global state
//

var has_booted: bool = false;
var graphics_context: GraphicsContext = undefined;
var running = true;
var layer_stack: LayerStack.LayerStack(MAX_LAYERS, MAX_OVERLAYS) = undefined;
var sandbox_sdl_layer: SandboxSdlLayer = undefined;
var sandbox_vulkan_layer: SandboxVulkanLayer = undefined;

pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    errdefer shutdown();
    // tracy.frameMarkStart("Main");

    graphics_context = try GraphicsContext.init(allocator);

    layer_stack = try LayerStack.LayerStack(MAX_LAYERS, MAX_OVERLAYS).init();

    // sandbox_sdl_layer = SandboxSdlLayer.init(allocator, config, &graphics_context);
    // try pushLayer(sandbox_sdl_layer.interface());
    sandbox_vulkan_layer = SandboxVulkanLayer.init(allocator, config, &graphics_context);
    try pushLayer(sandbox_vulkan_layer.interface());

    has_booted = true;
}

pub fn run() void {
    defer shutdown();

    graphics_context.startFramelimiter(FPS_LIMITER);
    while (running) {
        pollEvent();

        for (layer_stack.stack()) |layer| {
            layer.onUpdate();
        }

        if (graphics_context.framerate.skipDrawThreasholdReached()) {
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
                if (graphics_context.isWindowHandled(event.getWindow())) {
                    running = false;
                }
            },
            .window_display_changed => graphics_context.handleDisplayChanged(),
            else => {},
        }
    }
}

pub fn shutdown() void {
    if (has_booted) {
        for (layer_stack.stack()) |layer| {
            layer.deinit();
        }
    }
    graphics_context.deinit();

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
