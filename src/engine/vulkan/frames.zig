const std = @import("std");
const log = std.log.scoped(.Swapchain);
const vk = @import("vulkan");
const GraphicsContext = @import("../../core/graphics_context.zig");
const Allocator = std.mem.Allocator;

const Swapchain = @import("swapchain.zig").Swapchain;
const CommandPool = @import("command_pool.zig");
const DescriptorAllocator = @import("descriptor.zig").DescriptorAllocator;
const SceneData = @import("../command.zig").SceneData;
const Buffer = @import("buffer.zig");

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
        _ = try ctx.device.waitForFences(&.{self.frame_fence}, .true, std.math.maxInt(u64));
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

pub const FrameData = struct {
    clear_color: vk.ClearValue = .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
    /// Contains the state if the last swapchain got an error
    swapchain_state: Swapchain.PresentState = .optimal,
    viewport: vk.Viewport = .{ .x = 0, .y = 0, .width = 0, .height = 0, .min_depth = 0, .max_depth = 1 },
    scissor: vk.Rect2D = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .height = 0, .width = 0 } },

    cmd_pool: CommandPool = undefined,
    cmd_buf: vk.CommandBuffer = undefined,

    desc_allocator: DescriptorAllocator = undefined,

    scene_data: SceneData = .{},
    scene_data_buffer: Buffer = undefined,

    pub fn setup(self: *FrameData, ctx: *const GraphicsContext, allocator: std.mem.Allocator) !void {
        self.cmd_pool = try CommandPool.create(ctx);

        const frame_sizes = &[_]DescriptorAllocator.PoolSizeRatio{
            .{ .vk_type = .storage_image, .ratio = 3 },
            .{ .vk_type = .storage_buffer, .ratio = 3 },
            .{ .vk_type = .uniform_buffer, .ratio = 3 },
            .{ .vk_type = .combined_image_sampler, .ratio = 4 },
        };
        self.desc_allocator = try DescriptorAllocator.init(allocator, ctx, 1000, frame_sizes);

        self.scene_data_buffer = try Buffer.create(ctx, @sizeOf(SceneData), .{
            .uniform_buffer_bit = true,
        }, .{ .host_visible_bit = true, .device_local_bit = true });
    }

    pub fn resize(self: *FrameData, extent: vk.Extent2D) void {
        self.viewport.width = @floatFromInt(extent.width);
        self.viewport.height = @floatFromInt(extent.height);
        self.scissor.extent = extent;
    }

    pub fn destroy(self: *FrameData, ctx: *const GraphicsContext) void {
        self.cmd_pool.destroy(ctx);
        self.desc_allocator.destroy(ctx);
        self.scene_data_buffer.destroy(ctx);
    }
};
