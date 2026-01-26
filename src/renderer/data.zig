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

pub const Indice = u16;

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

pub const Vertex = struct {
    // const binding_description = vk.VertexInputBindingDescription{
    //     .binding = 0,
    //     .stride = @sizeOf(Vertex),
    //     .input_rate = .vertex,
    // };
    //
    // const attribute_description = [_]vk.VertexInputAttributeDescription{
    //     .{
    //         .binding = 0,
    //         .location = 0,
    //         .format = .r32g32_sfloat,
    //         .offset = @offsetOf(Vertex, "pos"),
    //     },
    //     .{
    //         .binding = 0,
    //         .location = 1,
    //         .format = .r32g32_sfloat,
    //         .offset = @offsetOf(Vertex, "uv"),
    //     },
    //     .{
    //         .binding = 0,
    //         .location = 2,
    //         .format = .r32g32b32a32_sfloat,
    //         .offset = @offsetOf(Vertex, "col"),
    //     },
    // };

    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
    col: zm.F32x4,
};
