const std = @import("std");
const log = std.log.scoped(.Swapchain);
const vk = @import("vulkan");
const Allocator = std.mem.Allocator;

const Engine = @import("engine.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const CommandPool = @import("command_pool.zig").CommandPool;
const AllocatedCommandBuffer = @import("command_pool.zig").AllocatedCommandBuffer;
const DescriptorAllocator = @import("descriptor.zig").DescriptorAllocator;
const SceneData = @import("../command.zig").SceneData;
const Buffer = @import("buffer.zig");

const Frame = @This();

swap_image: SwapImage,

clear_color: vk.ClearValue = .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
/// Contains the state if the last swapchain got an error
swapchain_state: Swapchain.PresentState = .optimal,
viewport: vk.Viewport = .{ .x = 0, .y = 0, .width = 0, .height = 0, .min_depth = 0, .max_depth = 1 },
scissor: vk.Rect2D = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .height = 0, .width = 0 } },

cmd_pool: CommandPool = undefined,
cmd_buf: AllocatedCommandBuffer = undefined,

frame_descriptor: DescriptorAllocator = undefined,

scene_data: SceneData = .{},
scene_data_buffer: Buffer = undefined,

pub const SwapImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    pub fn init(engine: *Engine, image: vk.Image, format: vk.Format) !SwapImage {
        const view = try engine.ctx.device.createImageView(&.{
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
        errdefer engine.ctx.device.destroyImageView(view, null);

        const image_acquired = try engine.ctx.device.createSemaphore(&.{}, null);
        errdefer engine.ctx.device.destroySemaphore(image_acquired, null);

        const render_finished = try engine.ctx.device.createSemaphore(&.{}, null);
        errdefer engine.ctx.device.destroySemaphore(render_finished, null);

        const frame_fence = try engine.ctx.device.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer engine.ctx.device.destroyFence(frame_fence, null);

        return SwapImage{
            .image = image,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    pub fn deinit(self: SwapImage, engine: *Engine) void {
        self.waitForFence(engine) catch return;
        engine.ctx.device.destroyImageView(self.view, null);
        engine.ctx.device.destroySemaphore(self.image_acquired, null);
        engine.ctx.device.destroySemaphore(self.render_finished, null);
        engine.ctx.device.destroyFence(self.frame_fence, null);
    }

    pub fn waitForFence(self: SwapImage, engine: *Engine) !void {
        _ = try engine.ctx.device.waitForFences(&.{self.frame_fence}, .true, std.math.maxInt(u64));
    }
};

pub fn initSwapchainFrames(engine: *Engine, swapchain: vk.SwapchainKHR, format: vk.Format, allocator: Allocator) ![]Frame {
    const images = try engine.ctx.device.getSwapchainImagesAllocKHR(swapchain, allocator);
    defer allocator.free(images);

    const frames = try allocator.alloc(Frame, images.len);
    errdefer allocator.free(frames);

    errdefer for (frames[0..0]) |*frame| frame.destroy(engine);

    for (images, 0..) |image, i| {
        try frames[i].setup(engine, allocator, try SwapImage.init(engine, image, format));
    }

    return frames;
}

pub fn setup(self: *Frame, engine: *Engine, allocator: std.mem.Allocator, swap_image: SwapImage) !void {
    self.swap_image = swap_image;
    self.cmd_pool = try CommandPool.create(engine);

    const frame_sizes = &[_]DescriptorAllocator.PoolSizeRatio{
        .{ .vk_type = .storage_image, .ratio = 3 },
        .{ .vk_type = .storage_buffer, .ratio = 3 },
        .{ .vk_type = .uniform_buffer, .ratio = 3 },
        .{ .vk_type = .combined_image_sampler, .ratio = 4 },
    };
    self.frame_descriptor = try DescriptorAllocator.init(allocator, engine.ctx, 1000, frame_sizes);

    self.scene_data_buffer = try Buffer.create(engine.ctx, @sizeOf(SceneData), .{
        .uniform_buffer_bit = true,
    }, .{ .host_visible_bit = true, .device_local_bit = true });

    self.cmd_buf = try .allocate(engine, self.cmd_pool);
}

pub fn resize(self: *Frame, extent: vk.Extent2D) void {
    self.viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    self.scissor = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };
}

pub fn destroy(self: *Frame, engine: *Engine) void {
    self.swap_image.deinit(engine);
    self.cmd_buf.destroy(engine);
    self.cmd_pool.destroy(engine);
    self.frame_descriptor.destroy(engine.ctx);
    self.scene_data_buffer.destroy(engine.ctx);
}
