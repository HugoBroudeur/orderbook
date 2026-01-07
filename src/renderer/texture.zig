// The Texture are for the SDL implementation
const std = @import("std");
const sdl = @import("sdl3");

const Buffer = @import("buffer.zig");
const Sampler = @import("sampler.zig");
const GPU = @import("gpu.zig");

const Texture = @This();

gpu: *GPU,

ptr: sdl.gpu.Texture = undefined,
surface: ?sdl.surface.Surface = null,
width: u32 = 0,
heigth: u32 = 0,

is_in_gpu: bool = false,

pub fn init(gpu: *GPU) Texture {
    return .{ .gpu = gpu };
}

pub fn deinit(self: *Texture) void {
    self.destroy();
}

pub fn destroy(self: *Texture) void {
    if (self.is_in_gpu) {
        self.gpu.device.releaseTexture(self.ptr);
        self.ptr = undefined;
        self.heigth = 0;
        self.width = 0;
        self.is_in_gpu = false;
    }
}

pub fn createFromSurface(gpu: *GPU, surface: sdl.surface.Surface) !Texture {
    const ptr = try gpu.device.createTexture(.{
        .format = .r8g8b8a8_unorm,
        // .format = .b8g8r8a8_unorm,
        .texture_type = .two_dimensional_array,
        .width = @intCast(surface.getWidth()),
        .height = @intCast(surface.getHeight()),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = .{ .sampler = true },
    });

    return .{
        .gpu = gpu,
        .ptr = ptr,
        .is_in_gpu = true,
        .surface = surface,
        .width = @intCast(surface.getWidth()),
        .heigth = @intCast(surface.getHeight()),
    };
}

pub fn createFromPtr(gpu: *GPU, ptr: sdl.gpu.Texture, width: u32, heigth: u32) Texture {
    return .{
        .gpu = gpu,
        .ptr = ptr,
        .is_in_gpu = true,
        .width = width,
        .heigth = heigth,
    };
}

pub fn upload(self: *Texture, copy_pass: sdl.gpu.CopyPass, tb: Buffer.TransferBuffer) void {
    copy_pass.uploadToTexture(.{ .transfer_buffer = tb.ptr, .offset = 0 }, .{
        .texture = self.ptr,
        .width = @intCast(self.surface.?.getWidth()),
        .height = @intCast(self.surface.?.getHeight()),
        .depth = 1,
    }, false);
}

pub fn bind(self: *Texture, render_pass: sdl.gpu.RenderPass, sampler: Sampler) void {
    render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.ptr, .sampler = sampler.ptr }});
}

pub const TextureFormat = struct {
    ptr: sdl.gpu.TextureFormat,
};
