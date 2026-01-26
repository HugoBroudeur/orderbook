const std = @import("std");
const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");
const RenderPass = @import("render_pass.zig");
const Swapchain = @import("swapchain.zig").Swapchain;

const Framebuffer = @This();

allocator: std.mem.Allocator,
vk_framebuffers: []vk.Framebuffer,

pub fn create(ctx: *const GraphicsContext, allocator: std.mem.Allocator, render_pass: RenderPass, swapchain: Swapchain) !Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| ctx.device.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        fb.* = try ctx.device.createFramebuffer(&.{
            .render_pass = render_pass.vk_render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swapchain.swap_images[i].view),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return .{ .vk_framebuffers = framebuffers, .allocator = allocator };
}

pub fn destroy(self: *Framebuffer, ctx: *GraphicsContext) void {
    for (self.vk_framebuffers) |framebuffer| {
        ctx.device.destroyFramebuffer(framebuffer, null);
    }
    self.allocator.free(self.vk_framebuffers);
}
