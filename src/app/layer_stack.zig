const std = @import("std");
const Layer = @import("layer.zig");

const LayerStack = @This();

allocator: std.mem.Allocator,
layers: std.ArrayList(*Layer),
len: u32,
layer_cur_pos: u32,
overlay_cur_pos: u32,

pub fn init(allocator: std.mem.Allocator) !LayerStack {
    const layer_cur_pos: u32 = 0;
    const overlay_cur_pos: u32 = 1;

    return .{
        .allocator = allocator,
        .layers = try .initCapacity(allocator, layer_cur_pos + overlay_cur_pos + 1),
        .len = 0,
        .layer_cur_pos = layer_cur_pos,
        .overlay_cur_pos = overlay_cur_pos,
    };
}

pub fn deinit(self: *LayerStack) void {
    self.layers.deinit(self.allocator);
}

pub fn pushLayer(self: *LayerStack, layer: *Layer) !void {
    if (self.len + 1 > self.layers.capacity) {
        try self.layers.ensureTotalCapacity(self.allocator, self.layers.capacity + 2);
    }

    self.layers.insertAssumeCapacity(self.layer_cur_pos, layer);
    self.len += 1;
    self.layer_cur_pos += 1;
    self.overlay_cur_pos += 1;
}

pub fn pushOverlay(self: *LayerStack, overlay: *Layer) !void {
    if (self.len + 1 > self.layers.capacity) {
        try self.layers.ensureTotalCapacity(self.allocator, self.layers.capacity + 2);
    }

    self.layers.insertAssumeCapacity(self.overlay_cur_pos, overlay);
    self.len += 1;
    self.overlay_cur_pos += 1;
}

pub fn popLayer(self: *LayerStack, layer: *Layer) void {
    for (0..self.layer_cur_pos) |i| {
        if (self.layers[i] == layer) {
            _ = self.layers.swapRemove(i);
            self.len -= 1;
            self.layer_cur_pos -= 1;
            self.overlay_cur_pos -= 1;
        }
    }
}

pub fn popOverlay(self: *LayerStack, overlay: *Layer) void {
    for (self.layer_cur_pos..self.overlay_cur_pos) |i| {
        if (self.layers[i] == overlay) {
            _ = self.layers.swapRemove(i);
            self.len -= 1;
            self.overlay_cur_pos -= 1;
        }
    }
}
