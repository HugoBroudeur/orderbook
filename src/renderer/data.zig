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

pub const WorldMatrix3D = zm.Mat;
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
