const std = @import("std");
const sdl = @import("sdl3");

const Window = @import("window.zig");

const Display = @This();

available_displays: []sdl.video.Display,
current_ptr: ?sdl.video.Display = null,
name: []const u8 = undefined,
refresh_rate: f32 = 0,

pub fn init() !Display {
    return .{ .available_displays = try sdl.video.getDisplays() };
}

pub fn detectCurrentDisplay(self: *Display, window: *Window) void {
    const display = window.ptr.getDisplayForWindow() catch {
        // Window is minised
        return;
    };
    if (self.current_ptr != null and self.current_ptr.?.value == display.value) return;
    self.current_ptr = display;
    self.name = display.getName() catch "";

    const mode = display.getCurrentMode() catch {
        // ?
        return;
    };
    self.refresh_rate = if (mode.refresh_rate) |rate| rate else 0;

    std.log.info(
        \\==================== Display in use =====================
        \\  Display Name                     : {s}
        \\  Display Pixel density            : {}
        \\  Display refresh_rate             : {?}
    ,
        .{
            self.name,
            mode.pixel_density,
            mode.refresh_rate,
        },
    );
}
