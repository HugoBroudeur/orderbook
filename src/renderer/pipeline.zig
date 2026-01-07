// The Pipeline is for the SDL implementation

const std = @import("std");
const sdl = @import("sdl3");
const zm = @import("zmath");

const Shader = @import("shader.zig");
const Texture = @import("texture.zig");
const GPU = @import("gpu.zig");

const Pipeline = @This();

const CreateShaderParam = struct {
    shader_name: []const u8,
    uniforms: u32,
    samplers: u32,
};

gpu: *GPU,

ptr: sdl.gpu.GraphicsPipeline,
is_in_gpu: bool = false,

pub const GraphicPipelineInfo = struct {
    pipeline: sdl.gpu.GraphicsPipeline,
    vertex_size: u32,
    index_size: u32,
};

const UV = packed struct {
    u: f32,
    v: f32,
};

pub const PositionTextureVertex = packed struct {
    pos: zm.Vec,
    uv: UV,
};

pub const D2Vertex = packed struct {
    pos: @Vector(2, f32),
    uv: UV,
    col: zm.F32x4,
};

pub fn init(gpu: *GPU) Pipeline {
    return .{
        .gpu = gpu,
    };
}

pub fn deinit(self: *Pipeline) void {
    self.destroy();
}

pub fn destroy(self: *Pipeline) void {
    if (self.is_in_gpu) {
        self.gpu.device.releaseGraphicsPipeline(self.ptr);
        self.ptr = undefined;
        self.is_in_gpu = false;
    }
}

pub fn bind(self: *Pipeline, render_pass: sdl.gpu.RenderPass) void {
    render_pass.bindGraphicsPipeline(self.ptr);
}

pub fn createDemoPipeline(gpu: *GPU, format: Texture.TextureFormat) !Pipeline {
    std.log.info("[Pipeline.createDemoPipeline]", .{});

    var vertex_shader = try Shader.create(gpu, .{
        .shader_name = "triangle.vert",
        .uniforms = 1,
        .samplers = 0,
    });
    defer vertex_shader.deinit();
    var fragment_shader = try Shader.create(gpu, .{
        .shader_name = "triangle.frag",
        .uniforms = 0,
        .samplers = 0,
    });
    defer fragment_shader.deinit();

    return create(gpu, .{
        .texture_format = format,
        .fragment_shader = fragment_shader,
        .vertex_shader = vertex_shader,
    });
}

pub fn createUiPipeline(gpu: *GPU, format: Texture.TextureFormat) !Pipeline {
    std.log.info("[Pipeline.createUiPipeline]", .{});

    var vertex_shader = try Shader.create(gpu, .{
        .shader_name = "2d_ui.vert",
        .uniforms = 1,
        .samplers = 0,
    });
    defer vertex_shader.deinit();
    var fragment_shader = try Shader.create(gpu, .{
        .shader_name = "2d_ui.frag",
        .uniforms = 0,
        .samplers = 1,
    });
    defer fragment_shader.deinit();

    return create(gpu, .{
        .texture_format = format,
        .fragment_shader = fragment_shader,
        .vertex_shader = vertex_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{
                .{
                    .slot = 0,
                    .pitch = @sizeOf(D2Vertex),
                    .input_rate = .vertex,
                },
            },
            .vertex_attributes = &[_]sdl.gpu.VertexAttribute{
                .{
                    .buffer_slot = 0,
                    .format = .f32x2,
                    .location = 0,
                    .offset = 0,
                },
                .{
                    .buffer_slot = 0,
                    .format = .f32x2,
                    .location = 1,
                    .offset = @sizeOf(f32) * 2,
                },
                .{
                    .buffer_slot = 0,
                    .format = .f32x4,
                    .location = 2,
                    .offset = @sizeOf(f32) * 4,
                },
            },
        },
    });
}

pub fn createSolidPipeline(gpu: *GPU, format: Texture.TextureFormat) !Pipeline {
    std.log.info("[Pipeline.createSolidPipeline] ", .{});

    var vertex_shader = try Shader.create(gpu, .{
        .shader_name = "texture_quad.vert",
        .uniforms = 1,
        .samplers = 0,
    });
    defer vertex_shader.deinit();
    var fragment_shader = try Shader.create(gpu, .{
        .shader_name = "texture_quad.frag",
        .uniforms = 1,
        .samplers = 1,
    });
    defer fragment_shader.deinit();

    return create(gpu, .{
        .texture_format = format,
        .fragment_shader = fragment_shader,
        .vertex_shader = vertex_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{
                .{
                    .slot = 0,
                    .pitch = @sizeOf(PositionTextureVertex),
                    .input_rate = .vertex,
                },
            },
            .vertex_attributes = &[_]sdl.gpu.VertexAttribute{
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
            },
        },
    });
}

pub const CreatePipelineDesc = struct {
    vertex_shader: Shader,
    fragment_shader: Shader,
    texture_format: Texture.TextureFormat,
    vertex_input_state: ?sdl.gpu.VertexInputState = null,
};
pub fn create(gpu: *GPU, desc: CreatePipelineDesc) !Pipeline {
    var pipeline_create_info: sdl.gpu.GraphicsPipelineCreateInfo = .{
        .vertex_shader = desc.vertex_shader.ptr,
        .fragment_shader = desc.fragment_shader.ptr,
        .primitive_type = .triangle_list,
        .target_info = .{
            .color_target_descriptions = &.{.{ .format = desc.texture_format.ptr }},
        },
    };

    if (desc.vertex_input_state) |vis| {
        pipeline_create_info.vertex_input_state = vis;
    }

    const ptr = try gpu.device.createGraphicsPipeline(pipeline_create_info);
    return .{ .gpu = gpu, .is_in_gpu = true, .ptr = ptr };
}
