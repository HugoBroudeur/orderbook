const std = @import("std");
const assert = std.debug.assert;
const sdl = @import("sdl3");
const dvui = @import("dvui");
const VulkanBackend = @import("../editor/dvui/vulkan_backend.zig");
const a = @import("sdl3gpu-backend");

const Event = @import("../events/event.zig");

const Config = @import("../config.zig");
const DrawCommand = @import("../engine/command.zig"); // 2D
const EcsManager = @import("../game/ecs_manager.zig");
const FontManager = @import("../game/font_manager.zig");
const Layer = @import("../core/layer.zig");
const Engine = @import("../engine/vulkan/engine.zig");

const EditorLayer = @This();

allocator: std.mem.Allocator,
io: std.Io,
label: []const u8 = "Editor Layer",
config: Config,
engine: *Engine,
window: dvui.Window = undefined,

backend: VulkanBackend = undefined,

pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config, engine: *Engine) EditorLayer {
    return .{
        .allocator = allocator,
        .config = config,
        .engine = engine,
        .io = io,
    };
}

pub fn deinit(self: *EditorLayer) void {
    self.backend.deinit();
}

pub fn interface(self: *EditorLayer) Layer {
    return Layer.init(self);
}

pub fn getLabel(self: *EditorLayer) []const u8 {
    return self.label;
}

pub fn onAttach(self: *EditorLayer) !void {
    dvui.Examples.show_demo_window = true;
    self.backend = try VulkanBackend.init(self.allocator, self.io, self.engine);
    // self.window = try dvui.Window.init(@src(), self.allocator, self.backend.backend(), .{});
}

pub fn onUpdate(self: *EditorLayer) void {
    _ = self;
    // self.backend.swapchain_image_view = self.engine.getCurrentFrame().swap_image.view;
    // self.backend.swapchain_format = self.engine.swapchain.surface_format.format;
    // self.backend.render_extent = self.engine.draw_extent;
    // self.backend.last_pixel_size = .{
    //     .w = @floatFromInt(self.engine.draw_extent.width),
    //     .h = @floatFromInt(self.engine.draw_extent.height),
    // };

    // const nstime = self.window.beginWait(false);
    // self.window.begin(nstime) catch return;
    // _ = self.backend.addAllEvents(&self.window) catch {};

    // dvui.Examples.demo(.full);

    // _ = self.window.end(.{ .manage_backend = false }) catch return;

    // if (self.window.cursorRequestedFloating()) |cursor| self.backend.setCursor(cursor);
    // self.backend.textInputRect(self.window.textInputRequested());
}

pub fn onEvent(self: *EditorLayer, ev: Event) void {
    _ = self;
    _ = ev;
    // switch (ev.ptr) {
    //     .quit => {
    //         const close_event: sdl.events.Event = .{ .quit = .{ .common = .{ .timestamp = 0 } } };
    //         sdl.events.push(close_event) catch {};
    //     },
    //     .key_down => {
    //         switch (ev.ptr.key_down.key.?) {
    //             .escape => {
    //                 const close_event: sdl.events.Event = .{ .window_close_requested = .{ .id = self.engine.ctx.getWindowId(), .common = .{ .timestamp = 0 } } };
    //                 sdl.events.push(close_event) catch {};
    //             },
    //             else => {},
    //         }
    //     },
    //     else => {},
    // }
    //
    // self.backend.addEvent(ev.ptr);
}
