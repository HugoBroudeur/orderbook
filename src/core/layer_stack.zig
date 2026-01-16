const std = @import("std");
const Layer = @import("layer.zig");

pub fn LayerStack(comptime max_layers: usize, comptime max_overlays: usize) type {
    return struct {
        const This = @This();
        layers: Stack(Layer, max_layers),
        overlays: Stack(Layer, max_overlays),

        pub fn init() !This {
            return .{
                .layers = .init(),
                .overlays = .init(),
            };
        }

        pub fn stack(self: *This) [max_layers + max_overlays]Layer {
            var out: [max_layers + max_overlays]Layer = undefined;

            out[0..max_layers].* = self.layers.items();
            out[max_layers .. max_layers + max_overlays].* = self.overlays.items();
            return out;
        }

        pub fn pushLayer(self: *This, layer: Layer) void {
            self.layers.push(layer);
        }

        pub fn pushOverlay(self: *This, overlay: Layer) void {
            self.overlays.push(overlay);
        }

        pub fn popLayer(self: *This, layer: Layer) void {
            self.layers.pop(layer);
        }

        pub fn popOverlay(self: *This, overlay: Layer) void {
            self.overlays.pop(overlay);
        }
    };
}

fn Stack(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        stack: [size]T,
        cur_pos: u32,

        fn init() Self {
            return .{ .cur_pos = 0, .stack = @splat(undefined) };
        }

        pub fn items(self: *Self) [size]T {
            return self.stack;
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
