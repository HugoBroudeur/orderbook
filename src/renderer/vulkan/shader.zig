// The Shader is for the SDL implementation

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.Shader);
const sdl = @import("sdl3");
const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");

const CreateShaderParam = struct {
    /// Name must be in .spv, the shader must be located in src/shaders/
    /// example: .name = "triangle.spv"
    name: []const u8,
    stage: ShaderStage,
};

pub const ShaderStage = enum {
    vertex,
    fragment,
    pub fn toShaderStageFlag(self: ShaderStage) vk.ShaderStageFlags {
        return switch (self) {
            .vertex => .{ .vertex_bit = true },
            .fragment => .{ .fragment_bit = true },
        };
    }
};

const Shader = @This();

stage: ShaderStage,
name: []const u8,
entrypoint: []const u8,
bytecode: []const u8,

module: vk.ShaderModule = undefined,

pub fn destroy(self: *Shader, ctx: *GraphicsContext) void {
    ctx.device.destroyShaderModule(self.module, null);
}

// Only support SPIR-V
pub fn create(ctx: *GraphicsContext, data: CreateShaderParam) !Shader {
    std.log.info("[Shader.create] {s} - {}", .{ data.name, data.stage });

    const extention = std.fs.path.extension(data.name);
    if (!std.mem.eql(u8, ".spv", extention)) {
        log.err("Shader extension '{s}' not supported, only '.spv' is supported (SPIR-V).", .{extention});
        return error.InvalidShaderExtension;
    }

    const entrypoint = @tagName(data.stage);

    const bytecode = try getShaderByteCode(data.name);

    var shader: Shader = .{ .name = data.name, .entrypoint = entrypoint, .bytecode = bytecode, .stage = data.stage };

    shader.module = try ctx.device.createShaderModule(&shader.moduleCreateInfo(), null);

    return shader;
}

pub fn moduleCreateInfo(
    self: *Shader,
) vk.ShaderModuleCreateInfo {
    const bytes_unaligned = std.mem.bytesAsSlice(u32, self.bytecode);
    const bytes: []const u32 = @alignCast(bytes_unaligned);

    return .{
        .code_size = self.bytecode.len,
        .p_code = bytes.ptr,
    };
}

fn bytesToU32Ptr(bytes: []const u8) ![*]const u32 {
    if (bytes.len % 4 != 0)
        return error.InvalidSpirv;

    const unaligned = std.mem.bytesAsSlice(u32, bytes);
    return (@alignCast(unaligned));
}

pub fn toShaderStageFlag(self: Shader) vk.ShaderStageFlags {
    return self.stage.toShaderStageFlag();
}

pub fn getPipelineShaderStageCreateInfo(self: *Shader) vk.PipelineShaderStageCreateInfo {
    return .{
        .stage = self.toShaderStageFlag(),
        .module = self.module,
        .p_name = @ptrCast(self.entrypoint),
    };
}

fn getShaderByteCode(name: []const u8) ![]const u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const shader_file_path = try std.fmt.bufPrint(&path_buf, "src/shaders/{s}", .{name});
    log.debug("Loading Shader: {s}", .{shader_file_path});

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

pub const ShaderDataType = enum {
    None,
    Float,
    Float2,
    Float3,
    Float4,
    Mat3,
    Mat4,
    Int,
    Int2,
    Int3,
    Int4,
    Bool,

    pub fn size(self: ShaderDataType) u32 {
        return switch (self) {
            .None => 0,
            .Float, .Float2, .Float3, .Float4, .Mat3, .Mat4 => @sizeOf(f32) * self.count(),
            .Int, .Int2, .Int3, .Int4 => @sizeOf(i32) * self.count(),
            .Bool => @sizeOf(bool) * self.count(),
        };
    }

    pub fn count(self: ShaderDataType) u32 {
        return switch (self) {
            .None => 0,
            .Float => 1,
            .Float2 => 2,
            .Float3 => 3,
            .Float4 => 4,
            .Mat3 => 3 * 3,
            .Mat4 => 4 * 4,
            .Int => 1,
            .Int2 => 2,
            .Int3 => 3,
            .Int4 => 4,
            .Bool => 1,
        };
    }

    pub fn toSdl(self: ShaderDataType) ?sdl.gpu.VertexElementFormat {
        return switch (self) {
            .None => null,
            .Float => .f32x1,
            .Float2 => .f32x2,
            .Float3 => .f32x3,
            .Float4 => .f32x4,
            .Mat3 => null,
            .Mat4 => null,
            .Int => .i32x1,
            .Int2 => .i32x2,
            .Int3 => .i32x3,
            .Int4 => .i32x4,
            .Bool => .u8x2,
        };
    }

    pub fn toVulkan(self: ShaderDataType) vk.Format {
        return switch (self) {
            .None => .undefined,
            .Float => .r32_sfloat,
            .Float2 => .r32g32_sfloat,
            .Float3 => .r32g32b32_sfloat,
            .Float4 => .r32g32b32a32_sfloat,
            .Mat3 => .undefined,
            .Mat4 => .undefined,
            .Int => .r32_sint,
            .Int2 => .r32g32_sint,
            .Int3 => .r32g32b32_sint,
            .Int4 => .r32g32b32a32_sint,
            .Bool => .undefined,
        };
    }
};
