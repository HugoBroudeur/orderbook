const std = @import("std");
const Layer = @import("layer.zig");

pub fn LayerStack(comptime max_layers: usize, comptime max_overlays: usize) type {
    return struct {
        layers: Stack(*Layer, max_layers),
        overlays: Stack(*Layer, max_overlays),

        pub fn init() !LayerStack {
            return .{
                .layers = .init(),
                .overlays = .init(),
            };
        }

        pub fn pushLayer(self: *LayerStack, layer: *Layer) !void {
            self.layers.push(layer);
        }

        pub fn pushOverlay(self: *LayerStack, overlay: *Layer) !void {
            self.overlays.push(overlay);
        }

        pub fn popLayer(self: *LayerStack, layer: *Layer) void {
            self.layers.pop(layer);
        }

        pub fn popOverlay(self: *LayerStack, overlay: *Layer) void {
            self.overlays.pop(overlay);
        }
    };
}

fn Stack(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        stack: [size]T,
        cur_pos: u32,

        fn init() !Self {
            return .{ .cur_pos = 0 };
        }

        fn push(self: *Self, el: T) void {
            std.debug.assert(self.cur_pos + 1 <= self.stack.len);

            self.stack[self.cur_pos] = el;
            self.cur_pos += 1;
        }

        fn pop(self: *Self, el: T) void {
            for (self.stack[0..self.cur_pos], 0..) |e, i| {
                if (e == el) {
                    std.debug.assert(self.cur_pos - 1 >= 0);
                    self.stack[i] = undefined;
                    self.cur_pos -= 1;
                }
            }
        }
    };
}
