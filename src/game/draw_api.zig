const std = @import("std");

const GPU = @import("gpu.zig");

const DrawApi = @This();

gpu: *GPU,

pub fn init(gpu: *GPU) DrawApi {
    return .{
        .gpu = gpu,
    };
}

pub fn deinit(self: *DrawApi) void {
    _ = self;
}

pub const DrawRectInput = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};
pub fn drawRect(self: *DrawApi, input: DrawRectInput) void {
    if (input.y > input.x) return;

    // self.gpu.vertex_buffers;

    _ = self;
}
