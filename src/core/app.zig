const std = @import("std");
const log = std.log.scoped(.app);
const assert = std.debug.assert;

const tracy = @import("tracy");
const Config = @import("../config.zig");
const Colors = @import("../game/colors.zig");

const sdl = @import("sdl3");
// const impl_sdl3 = @import("impl_sdl3");
// const impl_sdlgpu3 = @import("impl_sdlgpu3");

const ProjectManager = @import("../project/manager.zig");
const SceneManager = @import("../scene_management/manager.zig");
const AssetManager = @import("../resource_management/manager.zig");

const Layer = @import("layer.zig");
const LayerStack = @import("layer_stack.zig").LayerStack;
const Framerate = @import("framerate.zig");
const SandboxSdlLayer = @import("../layers/sandbox_sdl.zig");
const GameLayer = @import("../layers/game_layer.zig");
const RenderLayer = @import("../layers/render_layer.zig");
const EditorLayer = @import("../layers/editor_layer.zig");
const GraphicsContext = @import("graphics_context.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const Event = @import("../events/event.zig");
const World = @import("../ecs/world.zig");
const Systems = @import("../ecs/systems.zig");

const App = @This();

//
// Config
//
const FPS_THREASHOLD: u32 = 165;
const PROJECT_PATH = "$HOME/saved_projects/price_is_power";

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
render_layer: RenderLayer = undefined,
game_layer: GameLayer = undefined,
editor_layer: EditorLayer = undefined,
project_manager: ProjectManager = undefined,
scene_manager: SceneManager = undefined,
asset_manager: AssetManager = undefined,
world: World = undefined,

pub fn init(self: *App, config: Config) !void {
    // tracy.frameMarkStart("Main");

    self.graphics_context = try GraphicsContext.init(self.allocator);
    self.framerate = Framerate.init(@intFromFloat(self.graphics_context.display.refresh_rate));
    self.framerate.on();

    self.engine = try Engine.init(self.allocator, &self.graphics_context, self.io);
    try self.engine.setup();

    self.scene_manager.init(self.allocator, self.io, &self.world);
    self.asset_manager = .init(
        self.allocator,
        self.io,
        &self.engine,
    );
    // Must run before anything else can register a bindless texture:
    // `white` needs to claim slot 0 (the implicit fallback slot untextured
    // material fields default to).
    try self.asset_manager.initBasicTextures();
    self.project_manager = .init(self.allocator, self.io, config, &self.scene_manager, &self.asset_manager);

    self.world = try .init(self.allocator, self.io);

    try self.world.app.addResource(World.Components.RawInputQueue{ .allocator = self.allocator, .io = self.io });
    try self.world.app.addResource(World.Components.AssetManagerHandle{ .ptr = &self.asset_manager });
    try self.world.app.addPlugin(Systems.Plugins.Startup);

    self.render_layer = RenderLayer.init(self.allocator, self.io, &self.engine, &self.framerate, &self.world, &self.project_manager);
    self.game_layer = GameLayer.init(self.allocator, self.io, config, &self.engine, &self.framerate, &self.world);
    self.editor_layer = EditorLayer.init(self.allocator, self.io, config, &self.project_manager, &self.world, &self.engine);

    try self.project_manager.open(config.default_project_name);

    // Update order must be game -> editor -> render
    try self.pushLayer(self.game_layer.interface());
    try self.pushLayer(self.editor_layer.interface());
    try self.pushLayer(self.render_layer.interface());
}

pub fn run(self: *App) void {
    defer self.shutdown();

    self.framerate.resetTick();
    while (self.running) {
        self.pollEvent();

        for (self.layer_stack.stack().items) |layer| {
            layer.onUpdate();
        }

        self.world.app.runPar(World.Schedule.cleanup);
        self.world.app.flushCommands();

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

        // Events propagate in reverse update order (render -> editor -> game)
        // so the editor can swallow input that ImGui captures before the game
        // reacts to it.
        var event_swallowed = false;
        const layers = self.layer_stack.stack().items;
        var i = layers.len;
        while (i > 0) {
            i -= 1;
            if (!event_swallowed) {
                event_swallowed = layers[i].onEvent(ev);
            }
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

    // Engine is owned and deinited by the RenderLayer (layer loop above).
    self.graphics_context.deinit();
    self.project_manager.deinit();
    self.scene_manager.deinit();
    self.world.deinit();

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
