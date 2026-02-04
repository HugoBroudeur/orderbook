// This is a Window for the SDL implementation

const std = @import("std");
const sdl = @import("sdl3");
const vk = @import("vulkan");

const Event = @import("../events/event.zig");
const Display = @import("display.zig");

const Window = @This();

pub const WindowProps = struct {
    flags: sdl.video.Window.Flags = .{ .resizable = true, .hidden = false, .high_pixel_density = true, .vulkan = true },
    title: [:0]const u8 = "Price is Power",
    width: u32 = 1920,
    heigth: u32 = 1060,
};

ptr: sdl.video.Window,
title: [:0]const u8,

pub fn create(props: WindowProps) !Window {
    std.log.info("[Window] Creating window [\"{s}\"] ({}x{})", .{
        props.title,
        props.width,
        props.heigth,
    });
    std.debug.assert(sdl.wasInit(.{}).video);

    const ptr = try sdl.video.Window.init(props.title, props.width, props.heigth, props.flags);

    return .{ .ptr = ptr, .title = props.title };
}

pub fn deinit(self: *Window) void {
    self.ptr.deinit();
}

pub fn center(self: *Window, display: Display) void {
    self.ptr.setPosition(
        .{ .centered = display.current_ptr },
        .{ .centered = display.current_ptr },
    ) catch {};
}

pub fn getWidth(self: *const Window) usize {
    const size = self.ptr.getSize() catch .{ 0, 0 };
    return size.@"0";
}

pub fn getHeight(self: *const Window) usize {
    const size = self.ptr.getSize() catch .{ 0, 0 };
    return size.@"1";
}

pub fn setVSync(self: *Window, enabled: bool) void {
    if (enabled) {
        self.ptr.setSurfaceVSync(.{ .adaptive = undefined }) catch |err| {
            std.log.err("[Window] Can't set VSync \"adaptive\": {}. SDL error: {?s}", .{ err, sdl.errors.get() });
        };
        // self.ptr.setSurfaceVSync(.{ .on_each_num_refresh =  }) catch |err| {
        //     std.log.err("[Window] Can't set VSync \"on each num refresh\" with the framerate_limit {}: {}. SDL error: {?s}", .{ self.framerate_limit, err, sdl.errors.get() });
        //
        // };
    } else {
        self.ptr.setSurfaceVSync(null) catch |err| {
            std.log.err("[Window] Can't turn off VSync: {}. SDL error: {?s}", .{ err, sdl.errors.get() });
        };
    }
}

pub fn setSize(self: *Window, width: u32, height: u32) !void {
    const main_scale = try sdl.video.Display.getContentScale(try sdl.video.Display.getPrimaryDisplay());

    try self.ptr.setSize(@intFromFloat(@as(f32, @floatFromInt(width)) * main_scale), @intFromFloat(@as(f32, @floatFromInt(height)) * main_scale));
}

pub fn setTitle(self: *Window, title: [:0]const u8) !void {
    try self.ptr.setTitle(title);
}

pub fn setIcon(self: *Window, icon_path: [:0]const u8) !void {
    const icon_stream = try sdl.io_stream.Stream.initFromFile(icon_path, .read_text);
    const window_icon = try sdl.image.loadIcoIo(icon_stream);
    defer window_icon.deinit();
    try self.ptr.setIcon(window_icon);
}

pub fn toExtend2D(self: *Window) vk.Extent2D {
    return .{ .width = @intCast(self.getWidth()), .height = @intCast(self.getHeight()) };
}
