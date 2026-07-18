const std = @import("std");
const log = std.log.scoped(.runtime_layer);
const assert = std.debug.assert;
const sdl = @import("sdl3");
const vk = @import("vulkan");
const zclay = @import("zclay");

const Event = @import("../events/event.zig");
const EcsEvent = @import("../framework/event_queue.zig").Event;

const GraphicsContext = @import("../core/graphics_context.zig");
const ClayManager = @import("../game/clay_manager.zig");
const Config = @import("../config.zig");
const DbManager = @import("../game/db_manager.zig");
const EcsManager = @import("../game/ecs_manager.zig");
const FontManager = @import("../game/font_manager.zig");
const Layer = @import("../core/layer.zig");
const MarketManager = @import("../game/market_manager.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const Framerate = @import("../core/framerate.zig");
const World = @import("../ecs/world.zig");
// const UiManager = @import("../game/ui_manager.zig");
// const UiSystem = @import("../game/ecs/systems/ui_system.zig");

const RuntimeLayer = @This();

allocator: std.mem.Allocator,
io: std.Io,
label: []const u8 = "Sandbox Layer",
config: Config,
engine: *Engine,
world: *World,
framerate: *Framerate,

clay_manager: ClayManager = undefined,
db_manager: DbManager = undefined,
ecs_manager: EcsManager = undefined,
font_manager: FontManager = undefined,
market_manager: MarketManager = undefined,
// ui_manager: UiManager = undefined,
// ui_system: UiSystem = undefined,

pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config, engine: *Engine, framerate: *Framerate, world: *World) RuntimeLayer {
    return .{
        .allocator = allocator,
        .config = config,
        .engine = engine,
        .io = io,
        .framerate = framerate,
        .world = world,
    };
}

pub fn deinit(self: *RuntimeLayer) void {
    self.db_manager.deinit();
    self.market_manager.deinit();
    self.ecs_manager.deinit();
    self.font_manager.deinit();
    self.clay_manager.deinit();
}

pub fn interface(self: *RuntimeLayer) Layer {
    return Layer.init(self);
}

pub fn getLabel(self: *RuntimeLayer) []const u8 {
    return self.label;
}

pub fn onAttach(self: *RuntimeLayer) !void {
    self.db_manager = DbManager.init(self.allocator, self.config) catch |err| {
        log.err("Can't initiate DbManager: {}", .{err});
        return err;
    };
    // self.ui_system = UiSystem.init();
    self.font_manager = FontManager.init(self.allocator);
    // self.ui_manager = UiManager.init(self.allocator, &self.db_manager, &self.ui_system, &self.font_manager);
    self.market_manager = MarketManager.init(self.allocator, &self.db_manager);
    self.clay_manager = try ClayManager.init(self.allocator, &self.font_manager);
    self.ecs_manager = try EcsManager.init(self.allocator, &self.db_manager, &self.market_manager);

    self.ecs_manager.setup() catch |err| {
        log.err("Can't setup the EcsManager : {}", .{err});
        return err;
    };
    self.font_manager.setup() catch |err| {
        log.err("Can't setup the FontManager : {}", .{err});
        return err;
    };

    // Clay is now initialized and driven by the engine's UI renderer
    // (engine/graphics/ui.zig) — the legacy game-side ClayManager/FontManager
    // are superseded. Its setup is disabled so it doesn't re-initialize Clay's
    // global context out from under the engine.
    // self.clay_manager.setup() catch |err| {
    //     log.err("Can't setup the ClayManager : {}", .{err});
    //     return err;
    // };
    self.market_manager.setup(&self.ecs_manager) catch |err| {
        log.err("Can't setup the MarketManager : {}", .{err});
        return err;
    };
}

pub fn onUpdate(self: *RuntimeLayer) void {
    self.framerate.update_count = 0;
    while (self.framerate.shouldWait()) {}

    while (self.framerate.shouldUpdate()) {
        self.world.app.runPar(World.Schedule.pre_update);
        self.world.app.flushCommands();

        self.world.app.runPar(World.Schedule.update);
        self.world.app.flushCommands();

        self.world.app.runPar(World.Schedule.post_update);
        self.world.app.flushCommands();
    }
    assert(self.framerate.update_count > 0); // Make sure at least 1 update happened

    self.world.app.update(); // reset frame arena, progress world ticks.
}

pub fn onEvent(self: *RuntimeLayer, ev: Event) bool {
    switch (ev.ptr) {
        .quit => {
            const close_event: sdl.events.Event = .{ .quit = .{ .common = .{ .timestamp = 0 } } };
            sdl.events.push(close_event) catch {};
            return true;
        },
        .key_down => {
            switch (ev.ptr.key_down.key.?) {
                .escape => {
                    const close_event: sdl.events.Event = .{ .window_close_requested = .{ .id = self.engine.ctx.getWindowId(), .common = .{ .timestamp = 0 } } };
                    sdl.events.push(close_event) catch {};
                    return true;
                },
                else => {},
            }
        },
        else => {},
    }

    const queue = self.world.app.getResource(World.Components.RawInputQueue) catch null;
    if (null != queue) {
        var event: EcsEvent = .{ .ptr = ev.ptr, .type = .keyboard_pressed };
        queue.?.pushEvent(&event);
    }

    return self.ecs_manager.handleEvent(ev);
}
