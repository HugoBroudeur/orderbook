const vk = @import("vulkan");
const zm = @import("zmath");
const Data = @import("../data.zig");
const Primitive = @import("../../primitive.zig");
const Color = Primitive.Color;

// Global push constant
pub const GPUDrawPushConstants = extern struct {
    render_matrix: zm.Mat,
    vb_address: vk.DeviceAddress = undefined,
};
pub const GPUDrawPushConstants2D = extern struct {
    scale: Data.Scale2D,
    translate: Data.Translate2D,
    vb_address: vk.DeviceAddress = undefined,
};

// Vertex Data sent in Vertex buffers
pub const Vertex = extern struct {
    pos: [3]f32,
    uv_x: f32,
    normal: [3]f32,
    uv_y: f32,
    col: [4]f32,
    tangent: [3]f32,
    _unused_pad: f32 = 0,
};

/// Matrices are zmath row-vector layout, memcpy'd raw. Slang reads constant
/// buffers column-major (a free transpose): shaders must use mul(M, v), and
/// the view translation appears at view[0..2].w — see include/math.slang
/// calculateCameraPosition.
pub const SceneData = extern struct {
    view: zm.Mat = zm.identity(),
    proj: zm.Mat = zm.identity(),
    view_proj: zm.Mat = zm.identity(),
    ambient_color: [4]f32 = .{ 1, 1, 1, 0.2 },
    sunlight_direction: [4]f32 = .{ 0, 1, 0.5, 1 }, // w for sun power
    sunlight_color: [4]f32 = .{ 1, 1, 1, 1 },
    sunlight_specular_color: [4]f32 = .{ 1, 1, 1, 1 },
    time: f32 = 0,
};

// All are temporary for testing:
pub const triangle_vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.5, 0 }, .uv_x = 0.5, .uv_y = 0, .normal = .{ 0, 0, 1 }, .col = .{ 1, 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, 0 }, .uv_x = 1, .uv_y = 1, .normal = .{ 0, 0, 1 }, .col = .{ 0, 1, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5, 0 }, .uv_x = 0, .uv_y = 1, .normal = .{ 0, 0, 1 }, .col = .{ 0, 0, 1, 1 } },
};
pub const quad_vertices = [_]Vertex{
    .{ .pos = .{ 0.5, -0.5, 0 }, .uv_x = 1, .uv_y = 0, .normal = .{ 0, 0, 1 }, .col = .{ 1, 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, 0 }, .uv_x = 1, .uv_y = 1, .normal = .{ 0, 0, 1 }, .col = .{ 0.5, 0.5, 0.5, 1 } },
    .{ .pos = .{ -0.5, -0.5, 0 }, .uv_x = 0, .uv_y = 0, .normal = .{ 0, 0, 1 }, .col = .{ 0, 0, 1, 1 } },
    .{ .pos = .{ -0.5, 0.5, 0 }, .uv_x = 0, .uv_y = 1, .normal = .{ 0, 0, 1 }, .col = .{ 0, 1, 0, 1 } },
};
pub const quad_indices = [_]u32{
    0, 1, 2,
    2, 1, 3,
};
