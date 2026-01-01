const std = @import("std");
const gpu = std.gpu;

extern var color: @Vector(4, f32) addrspace(.output);

export fn main() callconv(.spirv_vertex) void {
    gpu.location(&color, 0);

    const vertices = [_]@Vector(4, f32){
        .{ 0.0, 0.5, 0.0, 1.0 },
        .{ 0.5, -0.5, 0.0, 1.0 },
        .{ -0.5, -0.5, 0.0, 1.0 },
    };
    const colors = [_]@Vector(4, f32){
        .{ 1.0, 0.0, 0.0, 1.0 },
        .{ 0.0, 1.0, 0.0, 1.0 },
        .{ 0.0, 0.0, 1.0, 1.0 },
    };

    color = colors[gpu.vertex_index];
    gpu.position_out.* = vertices[gpu.vertex_index];
}

// const common = @import("common.zig");
// const std = @import("std");
//
// /// Get the name of this shader file.
// fn shader_name() []const u8 {
//     return @src().file;
// }
//
// // Vertex shader variables.
// const vars = common.declareVertexShaderVars(shader_name()){};
//
// export fn main() callconv(.spirv_vertex) void {
//
//     // Bind vertex shader variables to the current shader.
//     common.bindVertexShaderVars(vars, shader_name());
//
//     // Since we are drawing 1 primitive triangle, the indices 0, 1, and 2 are the only vetices expected.
//     switch (std.gpu.vertex_index) {
//         0 => {
//             std.gpu.position_out.* = .{ -1, -1, 0, 1 };
//             vars.vert_out_color.* = .{ 1, 0, 0, 1 };
//         },
//         1 => {
//             std.gpu.position_out.* = .{ 1, -1, 0, 1 };
//             vars.vert_out_color.* = .{ 0, 1, 0, 1 };
//         },
//         else => {
//             std.gpu.position_out.* = .{ 0, 1, 0, 1 };
//             vars.vert_out_color.* = .{ 0, 0, 1, 1 };
//         },
//     }
// }
