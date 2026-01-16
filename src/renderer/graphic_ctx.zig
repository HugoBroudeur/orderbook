// This a Graphic Context for the SDL implementation

const GraphicCtx = @This();

const Window = @import("../core/window.zig");

window: *Window,

pub fn init(window: *Window) GraphicCtx {
    return .{ .window = window };
}

pub fn deinit(self: *GraphicCtx) void {
    _ = self;
}

pub fn swapBuffers(self: *GraphicCtx) void {
    _ = self;
}
