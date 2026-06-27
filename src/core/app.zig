const std = @import("std");
const log = std.log.scoped(.app);
const assert = std.debug.assert;

const tracy = @import("tracy");
const Config = @import("../config.zig");
const Colors = @import("../game/colors.zig");

const sdl = @import("sdl3");
// const impl_sdl3 = @import("impl_sdl3");
// const impl_sdlgpu3 = @import("impl_sdlgpu3");

const Layer = @import("layer.zig");
const LayerStack = @import("layer_stack.zig").LayerStack;
const Framerate = @import("framerate.zig");
const SandboxSdlLayer = @import("../layers/sandbox_sdl.zig");
const RuntimeLayer = @import("../layers/runtime.zig");
const EditorLayer = @import("../layers/editor.zig");
const GraphicsContext = @import("graphics_context.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const Event = @import("../events/event.zig");

const App = @This();

//
// Config
//
const FPS_THREASHOLD: u32 = 165;

//
// Global state
//
allocator: std.mem.Allocator,
io: std.Io,
framerate: Framerate = undefined,

graphics_context: GraphicsContext = undefined,
running: bool = true,
layer_stack: LayerStack,
engine: Engine = undefined,
sandbox_sdl_layer: SandboxSdlLayer = undefined,
runtime_layer: RuntimeLayer = undefined,
editor_layer: EditorLayer = undefined,

pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config) !App {
    // tracy.frameMarkStart("Main");

    var app: App = .{ .allocator = allocator, .io = io, .layer_stack = .init() };
    errdefer app.shutdown();

    app.graphics_context = try GraphicsContext.init(allocator);
    app.engine = try Engine.init(allocator, &app.graphics_context, io);
    app.engine.setup() catch |err| {
        log.err("Can't setup the Vulkan Engine : {}", .{err});
        return err;
    };
    app.framerate = Framerate.init(@intFromFloat(app.graphics_context.display.refresh_rate));
    app.framerate.on();

    app.runtime_layer = RuntimeLayer.init(allocator, io, config, &app.engine, &app.framerate);
    try app.pushLayer(app.runtime_layer.interface());

    // app.editor_layer = EditorLayer.init(allocator, io, config, &app.engine);
    // try app.pushLayer(app.editor_layer.interface());

    return app;
}

pub fn run(self: *App) void {
    defer self.shutdown();

    self.framerate.resetTick();
    while (self.running) {
        self.pollEvent();

        for (self.layer_stack.stack().items) |layer| {
            layer.onUpdate();
        }

        if (self.framerate.skipDrawThreasholdReached()) {
            log.err("PREVENTING FRAME LAG, EXITING NOW", .{});
            return;
        }
    }
}

pub fn pollEvent(self: *App) void {
    while (sdl.events.poll()) |event| {
        // _ = impl_sdl3.ImGui_ImplSDL3_ProcessEvent(@ptrCast(&event.toSdl()));
        const ev = Event.create(event);

        for (self.layer_stack.stack().items) |layer| {
            layer.onEvent(ev);
        }

        switch (event) {
            .quit => {
                self.running = false;
            },
            .window_close_requested => {
                if (self.graphics_context.isWindowHandled(event.getWindow())) {
                    self.running = false;
                }
            },
            .window_display_changed => self.handleDisplayChanged(),
            else => {},
        }
    }
}

pub fn shutdown(self: *App) void {
    for (self.layer_stack.stack().items) |layer| {
        layer.deinit();
    }

    self.engine.deinit();
    self.graphics_context.deinit();

    log.info("Closing... Good Bye!", .{});
    tracy.cleanExit(self.io);
}

pub fn handleDisplayChanged(self: *App) void {
    self.graphics_context.display.detectCurrentDisplay(&self.graphics_context.window);
    self.framerate.setTargetFps(@intFromFloat(self.graphics_context.display.refresh_rate));
}

pub fn pushLayer(self: *App, layer: Layer) !void {
    try self.layer_stack.pushLayer(self.allocator, layer);
    layer.onAttach() catch |err| {
        log.err("Error while attaching layer {s}. {}", .{ layer.getLabel(), err });
        return err;
    };
}

pub fn pushOverlay(self: *App, layer: Layer) !void {
    try self.layer_stack.pushOverlay(self.allocator, layer);
    layer.onAttach() catch |err| {
        log.err("Error while attaching layer {s}. {}", .{ layer.getLabel(), err });
        return err;
    };
}

test "app" {
    try std.testing.expectEqual(true, true);
}
