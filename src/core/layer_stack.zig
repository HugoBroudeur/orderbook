const std = @import("std");
const assert = std.debug.assert;
const Layer = @import("layer.zig");

pub const LayerStack = struct {
    _stack: std.ArrayList(Layer),

    cur_layer_len: usize = 0,
    cur_overlay_len: usize = 0,

    pub fn init() LayerStack {
        return .{
            ._stack = .empty,
        };
    }

    pub fn stack(self: *LayerStack) *std.ArrayList(Layer) {
        return &self._stack;
    }

    pub fn pushLayer(self: *LayerStack, allocator: std.mem.Allocator, layer: Layer) !void {
        try self._stack.insert(allocator, self.cur_layer_len, layer);
        self.cur_layer_len += 1;
    }

    pub fn pushOverlay(self: *LayerStack, allocator: std.mem.Allocator, overlay: Layer) !void {
        try self._stack.insert(allocator, self.cur_layer_len + self.cur_overlay_len, overlay);
        self.cur_overlay_len += 1;
    }

    pub fn popLayer(self: *LayerStack, layer: Layer) void {
        assert(self.cur_layer_len > 0);
        for (self._stack.items[0..self.cur_layer_len], 0..) |l, i| {
            if (std.mem.eql(u8, layer.getLabel(), l.getLabel())) {
                self._stack.orderedRemove(i);
                self.cur_layer_len -= 1;
            }
        }
    }

    pub fn popOverlay(self: *LayerStack, overlay: Layer) void {
        assert(self.cur_overlay_len > 0);
        for (self._stack.items[self.cur_layer_len..], 0..) |l, i| {
            if (std.mem.eql(u8, overlay.getLabel(), l.getLabel())) {
                self._stack.orderedRemove(i);
                self.cur_overlay_len -= 1;
            }
        }
    }
};

fn Stack(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        stack: [size]T,
        cur_pos: u32,

        fn init() Self {
            return .{ .cur_pos = 0, .stack = @splat(undefined) };
        }

        pub fn items(self: *Self) []T {
            return self.stack[0..self.cur_pos];
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
