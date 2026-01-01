const std = @import("std");
const sdl = @import("sdl3");

const PipelineManager = @This();

const CreateShaderParam = struct {
    shader_name: []const u8,
    uniforms: u32,
    samplers: u32,
};

allocator: std.mem.Allocator,
device: *sdl.gpu.Device,

const triangle_shader_spv = @embedFile("triangle.spv");

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
    std.log.debug("[PipelineManager.createShader] Shader File Path: {s}", .{shader_file_path});
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

// fn createPipeline(self: *RendererManager, primitive_type: sdl.gpu.PrimitiveType) !void {
//     std.log.info("[RendererManager.createPipeline] Vert Shader: {s} | Frag Shader: {s} | Primitive: {}", .{ vert_shader_name, frag_shader_name, primitive_type });
//     const vertex_shader = try self.createShader(vert_shader_bin, .vertex);
//     const frag_shader = try self.createShader(vert_shader_bin, .fragment);
//     // const frag_shader = try self.createShader(frag_shader_bin, .fragment);
//
//     const pipeline_create_info: sdl.gpu.GraphicsPipelineCreateInfo = .{
//         .vertex_shader = vertex_shader,
//         .fragment_shader = frag_shader,
//         .primitive_type = primitive_type,
//     };
//
//     const pipeline = try self.device.createGraphicsPipeline(pipeline_create_info);
//     try self.pipelines.append(self.allocator, pipeline);
// }

pub fn loadDemo(self: *PipelineManager, format: sdl.gpu.TextureFormat) !sdl.gpu.GraphicsPipeline {
    std.log.info("[PipelineManager.loadDemo] Create Demo Pipeline", .{});
    const vertex_shader = try self.createShader(.{
        .shader_name = "triangle.vert",
        .uniforms = 0,
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

    return try self.device.createGraphicsPipeline(pipeline_create_info);
}

// static SDL_GPUGraphicsPipeline* load_ui(
//     const SDL_GPUTextureFormat format)
// {
//     SDL_GPUGraphicsPipelineCreateInfo info =
//     {
//         .vertex_shader = load("fullscreen.vert", 0, 0),
//         .fragment_shader = load("ui.frag", 2, 1),
//         .target_info =
//         {
//             .num_color_targets = 1,
//             .color_target_descriptions = (SDL_GPUColorTargetDescription[])
//             {{
//                 .format = format,
//                 .blend_state =
//                 {
//                     .enable_blend = true,
//                     .src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA,
//                     .dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
//                     .src_color_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA,
//                     .dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
//                     .color_blend_op = SDL_GPU_BLENDOP_ADD,
//                     .alpha_blend_op = SDL_GPU_BLENDOP_ADD,
//                 },
//             }},
//         },
//     };
//     SDL_GPUGraphicsPipeline* pipeline = NULL;
//     if (info.vertex_shader && info.fragment_shader)
//     {
//         pipeline = SDL_CreateGPUGraphicsPipeline(device, &info);
//     }
//     if (!pipeline)
//     {
//         SDL_Log("Failed to create ui pipeline: %s", SDL_GetError());
//     }
//     SDL_ReleaseGPUShader(device, info.vertex_shader);
//     SDL_ReleaseGPUShader(device, info.fragment_shader);
//     return pipeline;
// }
