// This is the implementation for SDL3

const std = @import("std");
const Buffer = @import("buffer.zig");
const Texture = @import("texture.zig");
const sdl = @import("sdl3");
const GPU = @import("gpu.zig");

pub const Api = @This();

pub const VERTEX_BUFFER_SIZE = 64 * 1024; //64k vertices
pub const INDEX_BUFFER_SIZE = 64 * 1024; //64k indices

gpu: *GPU,

pub fn init(gpu: *GPU) Api {
    return .{ .gpu = gpu };
}

pub fn deinit(self: *Api) void {
    _ = self;
}

pub fn createGPU() !GPU {
    return try GPU.init();
}

pub fn createVertexBuffer(self: *Api, buffer_type: Buffer.VertexBufferType) !Buffer.VertexBuffer {
    var buffer = Buffer.VertexBuffer.init(buffer_type, self.gpu);
    try buffer.create();
    return buffer;
}

pub fn createIndexBuffer(self: *Api, buffer_type: Buffer.IndexBufferType) !Buffer.IndexBuffer {
    var buffer = Buffer.IndexBuffer.init(buffer_type, self.gpu);
    try buffer.create();
    return buffer;
}

pub fn createTransferBuffer(self: *Api, usage: sdl.gpu.TransferBufferUsage, size: u32) !Buffer.TransferBuffer {
    var buffer = Buffer.TransferBuffer.init(self.gpu, usage, size);
    try buffer.create();
    return buffer;
}

pub fn mapDataToGpu(tb: Buffer.TransferBuffer, data: []u8, cycle: bool) void {
    const gpu_tb_ptr = tb.mapToGpu(cycle);
    defer tb.unmapToGpu();

    std.mem.copyForwards(u8, gpu_tb_ptr, data);
}

pub const MapToTransferBuffer = struct {
    tb: Buffer.TransferBuffer,
    vertex_buffers: []const Buffer.VertexBuffer,
    index_buffers: []const Buffer.IndexBuffer,
    textures: []const Texture,
};

pub fn uploadDataToGpu(
    self: *Api,
    tb_mappings: []MapToTransferBuffer,
) void {
    const copy_pass = self.gpu.command_buffer.beginCopyPass();
    defer copy_pass.end();

    for (tb_mappings) |mapping| {
        if (!mapping.tb.has_data_mapped) {
            continue;
        }

        for (mapping.vertex_buffers) |buffer| {
            buffer.upload(copy_pass, mapping.tb);
        }
        for (mapping.index_buffers) |buffer| {
            buffer.upload(copy_pass, mapping.tb);
        }

        for (mapping.textures) |texture| {
            texture.upload(copy_pass, mapping.tb);
        }
    }
}
