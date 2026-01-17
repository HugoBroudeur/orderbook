const std = @import("std");
const assert = std.debug.assert;
const sdl = @import("sdl3");
const zclay = @import("zclay");

const Event = @import("../events/event.zig");

const Framerate = @import("../core/framerate.zig").Fixed;
const Window = @import("../core/window.zig");
const ClayManager = @import("../game/clay_manager.zig");
const Config = @import("../config.zig");
const DbManager = @import("../game/db_manager.zig");
const DrawCommand = @import("../renderer/command.zig"); // 2D
const EcsManager = @import("../game/ecs_manager.zig");
const FontManager = @import("../game/font_manager.zig");
const Layer = @import("../core/layer.zig");
const MarketManager = @import("../game/market_manager.zig");
const Renderer2D = @import("../renderer/renderer_2d.zig");
const SceneManager = @import("../game/scene_manager.zig");
// const UiManager = @import("../game/ui_manager.zig");
// const UiSystem = @import("../game/ecs/systems/ui_system.zig");

const SandboxLayer = @This();

allocator: std.mem.Allocator,
label: []const u8 = "Sandbox Layer",
config: Config,
window: *Window,
framerate: *Framerate,

clay_manager: ClayManager = undefined,
db_manager: DbManager = undefined,
draw_queue: DrawCommand.DrawQueue = undefined,
ecs_manager: EcsManager = undefined,
font_manager: FontManager = undefined,
market_manager: MarketManager = undefined,
renderer_2d: Renderer2D = undefined,
scene_manager: SceneManager = undefined,
// ui_manager: UiManager = undefined,
// ui_system: UiSystem = undefined,

pub fn init(
    allocator: std.mem.Allocator,
    config: Config,
    window: *Window,
    framerate: *Framerate,
) SandboxLayer {
    return .{
        .allocator = allocator,
        .config = config,
        .window = window,
        .framerate = framerate,
    };
}

pub fn deinit(self: *SandboxLayer) void {
    self.draw_queue.deinit();
    self.db_manager.deinit();
    self.market_manager.deinit();
    self.ecs_manager.deinit();
    self.scene_manager.deinit();
    self.renderer_2d.deinit();
    // self.ui_manager.deinit();
    self.font_manager.deinit();
    self.scene_manager.deinit();
}

pub fn interface(self: *SandboxLayer) Layer {
    return Layer.init(self);
}

pub fn getLabel(self: *SandboxLayer) []const u8 {
    return self.label;
}

pub fn onAttach(self: *SandboxLayer) !void {
    self.db_manager = DbManager.init(self.allocator, self.config) catch |err| {
        std.log.err("[Game][init] Can't initiate DbManager: {}", .{err});
        return err;
    };
    // self.ui_system = UiSystem.init();
    self.font_manager = FontManager.init(self.allocator);
    // self.ui_manager = UiManager.init(self.allocator, &self.db_manager, &self.ui_system, &self.font_manager);
    self.market_manager = MarketManager.init(self.allocator, &self.db_manager);
    self.clay_manager = try ClayManager.init(self.allocator, &self.font_manager);
    self.renderer_2d = try Renderer2D.init(self.allocator);
    self.draw_queue = try DrawCommand.DrawQueue.init(self.allocator, &self.renderer_2d);
    self.scene_manager = SceneManager.init(&self.draw_queue);
    self.ecs_manager = try EcsManager.init(self.allocator, &self.db_manager, &self.market_manager, &self.scene_manager);

    self.ecs_manager.setup() catch |err| {
        std.log.err("[App] Can't setup the EcsManager : {}", .{err});
        return err;
    };
    self.renderer_2d.setup(
        self.window,
        &self.font_manager,
        &self.clay_manager,
    ) catch |err| {
        std.log.err("[App] Can't setup the 2D Renderer : {}", .{err});
        return err;
    };
    self.font_manager.setup() catch |err| {
        std.log.err("[App] Can't setup the FontManager : {}", .{err});
        return err;
    };

    // self.ui_manager.setup(&self.ecs_manager) catch |err| {
    //     std.log.err("[App] Can't setup the UiManager : {}", .{err});
    //     return err;
    // };
    self.clay_manager.setup() catch |err| {
        std.log.err("[App] Can't setup the ClayManager : {}", .{err});
        return err;
    };
    self.market_manager.setup(&self.ecs_manager) catch |err| {
        std.log.err("[App] Can't setup the MarketManager : {}", .{err});
        return err;
    };
}
pub fn onUpdate(self: *SandboxLayer) void {
    if (self.framerate.isOn()) {
        self.framerate.update_count = 0;
        while (self.framerate.shouldWait()) {}

        while (self.framerate.shouldUpdate()) {
            self.ecs_manager.progress();
        }
        assert(self.framerate.update_count > 0); // Make sure at least 1 update happened
        if (self.framerate.shouldDraw()) {
            self.renderer_2d.startFrame();
            // self.ui_manager.renderFrame(&self.ecs_manager);
            self.scene_manager.render(&self.ecs_manager);
            // self.ecs_manager.render();
        }
    } else {
        self.ecs_manager.progress();
        self.renderer_2d.startFrame();
        // self.ui_manager.renderFrame(&self.ecs_manager);
        self.scene_manager.render(&self.ecs_manager);
        // self.ecs_manager.render();
        // self.ecs_manager.render();
    }
}
pub fn onEvent(self: *SandboxLayer, ev: Event) void {
    switch (ev.ptr) {
        .quit => {
            const close_event: sdl.events.Event = .{ .quit = .{ .common = .{ .timestamp = 0 } } };
            sdl.events.push(close_event) catch {};
        },
        .key_down => {
            switch (ev.ptr.key_down.key.?) {
                .escape => {
                    const close_event: sdl.events.Event = .{ .window_close_requested = .{ .id = self.window.ptr.getId() catch 0, .common = .{ .timestamp = 0 } } };
                    sdl.events.push(close_event) catch {};
                },
                else => {},
            }
        },
        else => {},
    }
}
