// The Pipeline is for the SDL implementation

const std = @import("std");
const sdl = @import("sdl3");
const zm = @import("zmath");

const Buffer = @import("buffer.zig");
const Shader = @import("shader.zig");
const Texture = @import("texture.zig");
const Data = @import("data.zig");
const GPU = @import("gpu.zig");
const RenderPass = @import("pass.zig").RenderPass;

const Pipeline = @This();

const MAX_VERTEX_ATTRIBUTES = 20;

const CreateShaderParam = struct {
    shader_name: []const u8,
    uniforms: u32,
    samplers: u32,
};

gpu: *GPU,

ptr: sdl.gpu.GraphicsPipeline,

pub const GraphicPipelineInfo = struct {
    pipeline: sdl.gpu.GraphicsPipeline,
    vertex_size: u32,
    index_size: u32,
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
    self.gpu.device.releaseGraphicsPipeline(self.ptr);
    self.ptr = undefined;
}

pub fn bind(self: *Pipeline, render_pass: RenderPass) void {
    render_pass.ptr.?.bindGraphicsPipeline(self.ptr);
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

pub fn create2DPipeline(gpu: *GPU, format: Texture.TextureFormat, layout: Buffer.IBufferLayout) !Pipeline {
    std.log.info("[Pipeline.create2DPipeline]", .{});

    var vertex_shader = try Shader.create(gpu, .{
        .shader_name = "2d.vert",
        .uniforms = 1,
        .samplers = 0,
    });
    defer vertex_shader.deinit();
    var fragment_shader = try Shader.create(gpu, .{
        .shader_name = "2d.frag",
        .uniforms = 0,
        .samplers = 1,
    });
    defer fragment_shader.deinit();

    return create(gpu, .{
        .texture_format = format,
        .fragment_shader = fragment_shader,
        .vertex_shader = vertex_shader,
        .layout = layout,
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
                    .pitch = @sizeOf(Data.PositionTextureVertex),
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
    layout: ?Buffer.IBufferLayout = null,
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

    if (desc.layout) |layout| {
        var attributes: [MAX_VERTEX_ATTRIBUTES]sdl.gpu.VertexAttribute = undefined;
        var count: u32 = 0;

        for (layout.getElements(), 0..) |el, i| {
            if (i >= MAX_VERTEX_ATTRIBUTES) return error.TooManyVertexAttributes;
            if (el.data_type.toSdl()) |format| {
                attributes[count] = .{
                    .buffer_slot = 0,
                    .format = format,
                    .location = count,
                    .offset = el.offset,
                };
                count += 1;
            }
        }

        pipeline_create_info.vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{
                .{
                    .slot = 0,
                    .pitch = layout.getStride(),
                    .input_rate = .vertex,
                },
            },
            .vertex_attributes = attributes[0..count],
        };
    }

    const ptr = try gpu.device.createGraphicsPipeline(pipeline_create_info);
    return .{ .gpu = gpu, .ptr = ptr };
}
