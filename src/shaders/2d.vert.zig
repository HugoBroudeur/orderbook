const std = @import("std");
const gpu = std.gpu;
const zm = @import("zmath");

const Vec2f = @Vector(2, f32);
const Vec4f = @Vector(4, f32);

extern var in_position: Vec4f addrspace(.input);
extern var in_uv: Vec2f addrspace(.input);

extern var out_color: Vec4f addrspace(.output);
extern var out_uv: Vec2f addrspace(.output);

const UniformBuffer = extern struct {
    mat: zm.Mat,
    color: Vec4f,
};

extern const ubo: UniformBuffer addrspace(.uniform);

export fn main() callconv(.spirv_vertex) void {
    gpu.location(&in_position, 0);
    gpu.location(&in_uv, 2);

    gpu.location(&out_color, 0);
    gpu.location(&out_uv, 1);

    gpu.binding(&ubo, 1, 0);

    out_color = ubo.color;
    out_uv = Vec2f{ -in_uv[0], in_uv[1] };

    const position = Vec4f{ in_position[0], in_position[1], 0.0, 1.0 };
    gpu.position_out.* = zm.mul(ubo.mat, position);
}
