const std = @import("std");
const log = std.log.scoped(.Swapchain);
const vk = @import("vulkan");
const GraphicsContext = @import("../../core/graphics_context.zig");
const Allocator = std.mem.Allocator;

pub const SwapImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    pub fn init(ctx: *const GraphicsContext, image: vk.Image, format: vk.Format) !SwapImage {
        const view = try ctx.device.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer ctx.device.destroyImageView(view, null);

        const image_acquired = try ctx.device.createSemaphore(&.{}, null);
        errdefer ctx.device.destroySemaphore(image_acquired, null);

        const render_finished = try ctx.device.createSemaphore(&.{}, null);
        errdefer ctx.device.destroySemaphore(render_finished, null);

        const frame_fence = try ctx.device.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer ctx.device.destroyFence(frame_fence, null);

        return SwapImage{
            .image = image,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    pub fn deinit(self: SwapImage, ctx: *const GraphicsContext) void {
        self.waitForFence(ctx) catch return;
        ctx.device.destroyImageView(self.view, null);
        ctx.device.destroySemaphore(self.image_acquired, null);
        ctx.device.destroySemaphore(self.render_finished, null);
        ctx.device.destroyFence(self.frame_fence, null);
    }

    pub fn waitForFence(self: SwapImage, ctx: *const GraphicsContext) !void {
        _ = try ctx.device.waitForFences(1, @ptrCast(&self.frame_fence), .true, std.math.maxInt(u64));
    }
};

pub fn initSwapchainImages(ctx: *const GraphicsContext, swapchain: vk.SwapchainKHR, format: vk.Format, allocator: Allocator) ![]SwapImage {
    const images = try ctx.device.getSwapchainImagesAllocKHR(swapchain, allocator);
    defer allocator.free(images);

    const swap_images = try allocator.alloc(SwapImage, images.len);
    errdefer allocator.free(swap_images);

    var i: usize = 0;
    errdefer for (swap_images[0..i]) |si| si.deinit(ctx);

    for (images) |image| {
        swap_images[i] = try SwapImage.init(ctx, image, format);
        i += 1;
    }

    return swap_images;
}
