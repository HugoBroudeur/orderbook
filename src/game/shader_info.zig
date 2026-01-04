const std = @import("std");
const zm = @import("zmath");
const sdl = @import("sdl3");
const ShaderInfo = @This();

vertex_shader_name: []const u8,
frament_shader_name: []const u8,

vertex_buffer_descriptions: []const sdl.gpu.VertexBufferDescription,
vertex_attributes: []const sdl.gpu.VertexAttribute,

const UV = packed struct {
    u: f32,
    v: f32,
};

pub const PositionTextureVertex = packed struct {
    pos: zm.Vec,
    uv: UV,
};
// const PositionTextureVertex = packed struct {
//     position: @Vector(3, f32),
//     uv: @Vector(2, f32),
// };

pub const TextureQuadShaderInfo: ShaderInfo = .{ .vertex_shader_name = "texture_quad.vert", .frament_shader_name = "texture_quad.frag", .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{
    .{
        .slot = 0,
        .pitch = @sizeOf(PositionTextureVertex),
        .input_rate = .vertex,
    },
}, .vertex_attributes = &[_]sdl.gpu.VertexAttribute{
    .{
        .buffer_slot = 0,
        .format = .f32x4,
        .location = 0,
        .offset = 0,
    },
    .{
        .buffer_slot = 0,
        .format = .f32x2,
        .location = 1,
        .offset = @sizeOf(zm.Vec),
    },
} };
