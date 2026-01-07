const std = @import("std");
const sdl = @import("sdl3");
const zm = @import("zmath");

const PipelineManager = @This();

const CreateShaderParam = struct {
    shader_name: []const u8,
    uniforms: u32,
    samplers: u32,
};

allocator: std.mem.Allocator,
device: *sdl.gpu.Device,

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

pub fn init(allocator: std.mem.Allocator, device: *sdl.gpu.Device) PipelineManager {
    return .{
        .allocator = allocator,
        .device = device,
    };
}

pub fn deinit(self: *PipelineManager) void {
    _ = self;
}

// Only support SPIR-V
fn createShader(self: *PipelineManager, data: CreateShaderParam) !sdl.gpu.Shader {
    const shader_name = data.shader_name;
    const uniforms = data.uniforms;
    const samplers = data.samplers;

    std.log.info("[PipelineManager.createShader] Create Shader {s}", .{shader_name});

    const extention = std.fs.path.extension(shader_name);

    var stage: ?sdl.gpu.ShaderStage = null;
    var entrypoint_name: [:0]const u8 = "";
    if (std.mem.eql(u8, extention, ".vert")) {
        stage = .vertex;
        entrypoint_name = "vertex";
    }

    if (std.mem.eql(u8, extention, ".frag")) {
        stage = .fragment;
        entrypoint_name = "fragment";
    }

    if (stage == null) {
        std.log.err("[PipelineManager.createShader] Shader extension '{s}' not supported, only '.vert' and '.frag' are supported.", .{extention});
        return error.InvalidShaderExtension;
    }

    const shader_file_path = try std.fmt.allocPrint(self.allocator, "src/shaders/{s}.spv", .{std.fs.path.stem(shader_name)});
    const file = try std.fs.cwd().openFile(shader_file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const shader_byte_code = try self.allocator.alloc(u8, file_size);

    _ = try file.readAll(shader_byte_code);

    // std.io.
    const shader_create_info: sdl.gpu.ShaderCreateInfo = .{
        .code = shader_byte_code,
        .entry_point = entrypoint_name,
        .format = .{ .spirv = true },
        .stage = stage.?,
        .num_samplers = samplers,
        .num_uniform_buffers = uniforms,
    };

    return try self.device.createShader(shader_create_info);
}

pub fn loadDemo(self: *PipelineManager, format: sdl.gpu.TextureFormat) !GraphicPipelineInfo {
    std.log.info("[PipelineManager.loadDemo] Create Demo Pipeline", .{});
    const vertex_shader = try self.createShader(.{
        .shader_name = "triangle.vert",
        .uniforms = 1,
        .samplers = 0,
    });
    defer self.device.releaseShader(vertex_shader);
    const fragment_shader = try self.createShader(.{
        .shader_name = "triangle.frag",
        .uniforms = 0,
        .samplers = 0,
    });
    defer self.device.releaseShader(fragment_shader);

    const pipeline_create_info: sdl.gpu.GraphicsPipelineCreateInfo = .{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .primitive_type = .triangle_list,
        .target_info = .{ .color_target_descriptions = &.{.{
            .format = format,
        }} },
    };

    return .{
        .pipeline = try self.device.createGraphicsPipeline(pipeline_create_info),
        .vertex_size = 0,
        .index_size = 0,
    };
}

pub fn loadUi(self: *PipelineManager, format: sdl.gpu.TextureFormat) !GraphicPipelineInfo {
    std.log.info("[PipelineManager.loadUi] Create Ui Pipeline", .{});

    const vertex_shader = try self.createShader(.{
        .shader_name = "2d_ui.vert",
        .uniforms = 1,
        .samplers = 0,
    });
    defer self.device.releaseShader(vertex_shader);
    const fragment_shader = try self.createShader(.{
        .shader_name = "2d_ui.frag",
        .uniforms = 0,
        .samplers = 1,
    });
    defer self.device.releaseShader(fragment_shader);

    const pipeline_create_info: sdl.gpu.GraphicsPipelineCreateInfo = .{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .primitive_type = .triangle_list,
        .target_info = .{
            .color_target_descriptions = &.{.{
                .format = format,
            }},
        },
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
    };

    return .{
        .pipeline = try self.device.createGraphicsPipeline(pipeline_create_info),
        .vertex_size = @sizeOf(D2Vertex),
        .index_size = @sizeOf(u16) * 3 * 2, // 2 triangles of 3 vertices each
    };
}

pub fn loadSolid(self: *PipelineManager, format: sdl.gpu.TextureFormat) !GraphicPipelineInfo {
    std.log.info("[PipelineManager.loadSolid] Create Solid Material Pipeline", .{});

    const vertex_shader = try self.createShader(.{
        .shader_name = "texture_quad.vert",
        .uniforms = 1,
        .samplers = 0,
    });
    defer self.device.releaseShader(vertex_shader);
    const fragment_shader = try self.createShader(.{
        .shader_name = "texture_quad.frag",
        .uniforms = 1,
        .samplers = 1,
    });
    defer self.device.releaseShader(fragment_shader);

    const pipeline_create_info: sdl.gpu.GraphicsPipelineCreateInfo = .{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .primitive_type = .triangle_list,
        .target_info = .{
            .color_target_descriptions = &.{.{
                .format = format,
                // .blend_state = .
            }},
        },
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
    };

    return .{
        .pipeline = try self.device.createGraphicsPipeline(pipeline_create_info),
        .vertex_size = @sizeOf(PositionTextureVertex) * 4,
        .index_size = @sizeOf(u16) * 3 * 2, // 2 triangles of 3 vertices each
    };
}
