// The Texture are for the SDL implementation
const std = @import("std");
const sdl = @import("sdl3");

const Buffer = @import("buffer.zig");
const Sampler = @import("sampler.zig");
const GPU = @import("gpu.zig");

const Texture = @This();

pub const TextureType = enum { two_dimensional, two_dimensional_array };

gpu: *GPU,

ptr: sdl.gpu.Texture = undefined,
surface: ?sdl.surface.Surface = null,
width: u32 = 0,
heigth: u32 = 0,

pub fn destroy(self: *Texture) void {
    self.gpu.device.releaseTexture(self.ptr);
    self.ptr = undefined;
    if (self.surface) |surface| {
        surface.deinit();
    }
    self.heigth = 0;
    self.width = 0;
}

pub fn createFromSurface(gpu: *GPU, surface: sdl.surface.Surface, tex_type: TextureType) !Texture {
    std.log.info("[Texture.createFromSurface] {s} [{} bytes] ({}px x {}px)", .{ @tagName(tex_type), surface.getPixels().?.len, surface.getWidth(), surface.getHeight() });

    const tt: sdl.gpu.TextureType = switch (tex_type) {
        .two_dimensional => .two_dimensional,
        .two_dimensional_array => .two_dimensional_array,
    };

    const ptr = try gpu.device.createTexture(.{
        .format = .r8g8b8a8_unorm,
        // .format = .b8g8r8a8_unorm,
        .texture_type = tt,
        .width = @intCast(surface.getWidth()),
        .height = @intCast(surface.getHeight()),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = .{ .sampler = true },
    });

    return .{
        .gpu = gpu,
        .ptr = ptr,
        .surface = surface,
        .width = @intCast(surface.getWidth()),
        .heigth = @intCast(surface.getHeight()),
    };
}

pub fn createFromPtr(gpu: *GPU, ptr: sdl.gpu.Texture, width: u32, heigth: u32) Texture {
    return .{
        .gpu = gpu,
        .ptr = ptr,
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
