const zm = @import("zmath");
const vk = @import("vulkan");

// const UV = packed struct {
//     u: f32,
//     v: f32,
// };

pub const PositionTextureVertex = packed struct {
    pos: zm.Vec,
    uv: @Vector(2, f32),
};

pub const D2Vertex = packed struct {
    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
    col: zm.F32x4,
};

pub const ViewProj = struct {
    view: zm.Mat,
    proj: zm.Mat,
};

pub const Scale2D = @Vector(2, f32);
pub const Translate2D = @Vector(2, f32);

// Define all the Shader data to render a quad and the number of indices for 1 quad
pub const Quad = struct {
    pub const VERTEX_COUNT: u32 = 4;
    pub const INDEX_COUNT: u32 = 6;

    pub const Vertex = packed struct {
        pos: @Vector(2, f32),
        uv: @Vector(2, f32),
        col: zm.F32x4,
    };
    pub const Indice = u16; // type of indice
};

pub const triangle_vertices = [_]Quad.Vertex{
    .{ .pos = .{ 0, -0.5 }, .uv = .{ 0.5, 0 }, .col = .{ 1, 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5 }, .uv = .{ 1, 1 }, .col = .{ 0, 1, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .uv = .{ 0, 1 }, .col = .{ 0, 0, 1, 1 } },
};
pub const quad_vertices = [_]Quad.Vertex{
    .{ .pos = .{ 0.5, -0.5 }, .uv = .{ 1, 0 }, .col = .{ 1, 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5 }, .uv = .{ 1, 1 }, .col = .{ 0.5, 0.5, 0.5, 1 } },
    .{ .pos = .{ -0.5, -0.5 }, .uv = .{ 0, 0 }, .col = .{ 0, 0, 1, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .uv = .{ 0, 1 }, .col = .{ 0, 1, 0, 1 } },
};
pub const quad_indices = [_]Quad.Indice{
    0, 1, 2,
    2, 1, 3,
};

pub const Indice = u16;
// Global 3D
pub const Vertex = packed struct {
    pos: @Vector(3, f32),
    uv_x: f32,
    normal: @Vector(3, f32),
    uv_y: f32,
    col: @Vector(4, f32),
};

const std = @import("std");

// Layout must match mesh.slang's Vertex struct (scalar/std430 layout, 48 bytes).
// If this test fails, the GPU is reading garbage for at least one field.
test "Vertex layout matches mesh.slang expectation" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(Vertex));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Vertex, "pos"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(Vertex, "uv_x"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Vertex, "normal"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(Vertex, "uv_y"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(Vertex, "col"));
}

test "Quad.Vertex layout matches 2d_bis.slang expectation (32 bytes, pos at 0)" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Quad.Vertex));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Quad.Vertex, "pos"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Quad.Vertex, "uv"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Quad.Vertex, "col"));
}
