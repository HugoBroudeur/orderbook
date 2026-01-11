// This is the implementation for SDL3

const std = @import("std");
const sdl = @import("sdl3");

const Asset = @import("asset.zig");
const Buffer = @import("buffer.zig").Buffer(.sdl);
const Camera = @import("camera.zig");
const CopyPass = @import("pass.zig").CopyPass;
const RenderPass = @import("pass.zig").RenderPass;
const Data = @import("data.zig");
const GPU = @import("gpu.zig");
const GraphicCtx = @import("graphic_ctx.zig");
const Pipeline = @import("pipeline.zig");
const Sampler = @import("sampler.zig");
const Texture = @import("texture.zig");
const Window = @import("../app/window.zig");

pub const Api = @This();

gpu: *GPU,

pub fn init(gpu: *GPU) Api {
    return .{ .gpu = gpu };
}

pub fn deinit(self: *Api) void {
    _ = self;
}

pub fn createGPU(window: *Window) !GPU {
    return try GPU.init(window);
}

pub fn createGraphicCtx(window: *Window) GraphicCtx {
    return GraphicCtx.init(window);
}

pub fn createVertexBuffer(self: *Api, comptime Vertex: type, comptime size: u32) !Buffer.VertexBuffer(Vertex, size) {
    return try Buffer.VertexBuffer(Vertex, size).create(self.gpu);
}

pub fn createIndexBuffer(self: *Api, comptime Vertex: type, comptime size: u32) !Buffer.VertexBuffer(Vertex, size) {
    return try Buffer.VertexBuffer(Vertex, size).create(self.gpu);
}

pub fn createTransferBuffer(self: *Api, comptime buf_type: Buffer.TransferBufferType, size: u32) !Buffer.TransferBuffer(buf_type) {
    return try Buffer.TransferBuffer(.upload).create(self.gpu, size);
}

pub fn createRenderPass(self: *Api) RenderPass {
    return RenderPass.init(self.gpu);
}

// pub fn createIndexBuffer(self: *Api, buffer_type: Buffer.IndexBufferType) !Buffer.IndexBuffer {
//     var buffer = Buffer.IndexBuffer.init(buffer_type, self.gpu);
//     try buffer.create();
//     return buffer;
// }

// pub fn createTransferBuffer(self: *Api, usage: sdl.gpu.TransferBufferUsage, size: u32) !Buffer.TransferBuffer {
//     var buffer = Buffer.TransferBuffer.init(self.gpu, usage, size);
//     try buffer.create();
//     return buffer;
// }

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
