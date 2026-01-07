// The Shader is for the SDL implementation

const std = @import("std");
const sdl = @import("sdl3");

const GPU = @import("gpu.zig");

const CreateShaderParam = struct {
    shader_name: []const u8,
    uniforms: u32,
    samplers: u32,
};

const Shader = @This();

gpu: *GPU,

ptr: sdl.gpu.Shader,
is_in_gpu: bool = false,

pub fn init(gpu: *GPU) Shader {
    return .{ .gpu = gpu };
}

pub fn deinit(self: *Shader) void {
    self.destroy();
}

pub fn destroy(self: *Shader) void {
    if (self.is_in_gpu) {
        self.gpu.device.releaseShader(self.ptr);
        self.ptr = undefined;
        self.is_in_gpu = false;
    }
}

// Only support SPIR-V
pub fn create(gpu: *GPU, data: CreateShaderParam) !Shader {
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

    const shader_byte_code = try getShaderByteCode(shader_name);

    const shader_create_info: sdl.gpu.ShaderCreateInfo = .{
        .code = shader_byte_code,
        .entry_point = entrypoint_name,
        .format = .{ .spirv = true },
        .stage = stage.?,
        .num_samplers = samplers,
        .num_uniform_buffers = uniforms,
    };

    const ptr = try gpu.device.createShader(shader_create_info);

    return .{ .ptr = ptr, .gpu = gpu, .is_in_gpu = true };
}

fn getShaderByteCode(name: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const shader_file_path = try std.fmt.bufPrint(&path_buf, "src/shaders/{s}.spv", .{std.fs.path.stem(name)});

    const file = try std.fs.cwd().openFile(shader_file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();

    // Use a stack buffer for shader code (adjust size as needed)
    var shader_buf: [1024 * 1024]u8 = undefined; // 1MB max
    if (file_size > shader_buf.len) return error.ShaderTooLarge;

    const shader_byte_code = shader_buf[0..file_size];
    _ = try file.readAll(shader_byte_code);

    return shader_byte_code;
}
