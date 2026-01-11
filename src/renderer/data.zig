const zm = @import("zmath");

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

pub const Indice = u16;

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
