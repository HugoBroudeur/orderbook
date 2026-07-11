const std = @import("std");
const log = std.log.scoped(.Swapchain);
const vk = @import("vulkan");
const Engine = @import("engine.zig");
const Allocator = std.mem.Allocator;
const AllocatedImage = @import("image.zig").AllocatedImage;
const Frame = @import("frames.zig");

pub const Swapchain = struct {
    pub const PresentState = enum {
        optimal,
        suboptimal,
    };

    allocator: Allocator,

    surface_format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    handle: vk.SwapchainKHR,

    frames: []Frame,
    image_index: u32,
    next_image_acquired: vk.Semaphore,

    // Flag if a window resize has happened
    resize_requested: bool = false,

    pub fn init(engine: *Engine, allocator: Allocator) !Swapchain {
        const width, const heigth = try engine.ctx.window.ptr.getMaximumSize();
        const extent: vk.Extent2D = .{ .width = @intCast(width), .height = @intCast(heigth) };
        const swapchain = try initRecycle(engine, allocator, extent, .null_handle);

        return swapchain;
    }

    pub fn initRecycle(engine: *Engine, allocator: Allocator, extent: vk.Extent2D, old_handle: vk.SwapchainKHR) !Swapchain {
        const caps = try engine.ctx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(engine.ctx.physical_device, engine.ctx.surface);
        const actual_extent = findActualExtent(caps, extent);
        if (actual_extent.width == 0 or actual_extent.height == 0) {
            return error.InvalidSurfaceDimensions;
        }

        const surface_format = try findSurfaceFormat(engine, allocator);
        const present_mode = try findPresentMode(engine, allocator);

        var image_count = caps.min_image_count + 1;
        if (caps.max_image_count > 0) {
            image_count = @min(image_count, caps.max_image_count);
        }

        const qfi = [_]u32{ engine.ctx.graphics_queue.family, engine.ctx.present_queue.family };
        const sharing_mode: vk.SharingMode = if (engine.ctx.graphics_queue.family != engine.ctx.present_queue.family)
            .concurrent
        else
            .exclusive;

        const handle = engine.ctx.device.createSwapchainKHR(&.{
            .surface = engine.ctx.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = actual_extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .image_sharing_mode = sharing_mode,
            .queue_family_index_count = qfi.len,
            .p_queue_family_indices = &qfi,
            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = .true,
            .old_swapchain = old_handle,
        }, null) catch {
            return error.SwapchainCreationFailed;
        };
        errdefer engine.ctx.device.destroySwapchainKHR(handle, null);

        if (old_handle != .null_handle) {
            // Apparently, the old swapchain handle still needs to be destroyed after recreating.
            engine.ctx.device.destroySwapchainKHR(old_handle, null);
        }

        const frames = try Frame.initSwapchainFrames(engine, handle, surface_format.format, allocator, extent);
        errdefer {
            for (frames) |*frame| frame.destroy(engine);
            allocator.free(frames);
        }

        var next_image_acquired = try engine.ctx.device.createSemaphore(&.{}, null);
        errdefer engine.ctx.device.destroySemaphore(next_image_acquired, null);

        const result = try engine.ctx.device.acquireNextImageKHR(handle, std.math.maxInt(u64), next_image_acquired, .null_handle);
        // event with a .suboptimal_khr we can still go on to present
        // if we error even for .suboptimal_khr the example will crash and segfault
        // on resize, since even the recreated swapchain can be suboptimal during a
        // resize.
        if (result.result == .not_ready or result.result == .timeout) {
            return error.ImageAcquireFailed;
        }

        std.mem.swap(vk.Semaphore, &frames[result.image_index].swap_image.image_acquired, &next_image_acquired);
        return Swapchain{
            .allocator = allocator,
            .surface_format = surface_format,
            .present_mode = present_mode,
            .extent = actual_extent,
            .handle = handle,
            .frames = frames,
            .image_index = result.image_index,
            .next_image_acquired = next_image_acquired,
            .resize_requested = false,
        };
    }

    fn deinitExceptSwapchain(self: Swapchain, engine: *Engine) void {
        for (self.frames) |*frame| frame.destroy(engine);
        self.allocator.free(self.frames);
        engine.ctx.device.destroySemaphore(self.next_image_acquired, null);
    }

    pub fn waitForAllFences(self: Swapchain) !void {
        for (self.frames) |si| si.waitForFence(self.ctx) catch {};
    }

    pub fn deinit(self: Swapchain, engine: *Engine) void {
        if (self.handle == .null_handle) return;
        self.deinitExceptSwapchain(engine);
        engine.ctx.device.destroySwapchainKHR(self.handle, null);
    }

    pub fn recreate(self: *Swapchain, engine: *Engine, new_extent: vk.Extent2D) !void {
        log.debug("call recreate, {}", .{new_extent});
        const allocator = self.allocator;
        const old_handle = self.handle;
        // Drain the device before destroying per-image semaphores and the old
        // swapchain. waitForFence on a single swap image is not enough —
        // semaphores belonging to other swap images may still be referenced by
        // submitted batches, and the presented image is still owned by the
        // present queue until the device is idle.
        try engine.ctx.device.deviceWaitIdle();
        self.deinitExceptSwapchain(engine);
        // set current handle to NULL_HANDLE to signal that the current swapchain does no longer need to be
        // de-initialized if we fail to recreate it.
        self.handle = .null_handle;
        self.* = initRecycle(engine, allocator, new_extent, old_handle) catch |err| switch (err) {
            error.SwapchainCreationFailed => {
                // we failed while recreating so our current handle still exists,
                // but we won't destroy it in the deferred deinit of this object.
                engine.ctx.device.destroySwapchainKHR(old_handle, null);
                return err;
            },
            else => return err,
        };
    }

    pub fn getCurrentFrame(self: *Swapchain) *Frame {
        return &self.frames[self.image_index];
    }

    pub fn currentImage(self: *Swapchain) AllocatedImage {
        return self.currentSwapImage().image;
    }

    pub fn currentSwapImage(self: *Swapchain) *const Frame.SwapImage {
        return &self.getCurrentFrame().swap_image;
    }

    pub fn present(self: *Swapchain, engine: *Engine) !PresentState {
        // Simple method:
        // 1) Acquire next image
        // 2) Wait for and reset fence of the acquired image
        // 3) Submit command buffer with fence of acquired image,
        //    dependendent on the semaphore signalled by the first step.
        // 4) Present current frame, dependent on semaphore signalled by previous step
        // Problem: This way we can't reference the current image while rendering.
        // Better method: Shuffle the steps around such that acquire next image is the last step,
        // leaving the swapchain in a state with the current image.
        // 1) Wait for and reset fence of current image
        // 2) Submit command buffer, signalling fence of current image and dependent on
        //    the semaphore signalled by step 4.
        // 3) Present current frame, dependent on semaphore signalled by the submit
        // 4) Acquire next image, signalling its semaphore
        // One problem that arises is that we can't know beforehand which semaphore to signal,
        // so we keep an extra auxilery semaphore that is swapped around

        // Step 1: Make sure the current frame has finished rendering
        const current = engine.getCurrentFrame().swap_image;
        const cmdbuf = engine.getCurrentFrame().cmd_buf.vk_command_buffer;
        try current.waitForFence(engine);
        try engine.ctx.device.resetFences(&.{current.frame_fence});

        // Step 2: Submit the command buffer
        var wait_info = Swapchain.createSemaphoreSubmitInfo(.{ .color_attachment_output_bit = true }, current.image_acquired);
        var signal_info = Swapchain.createSemaphoreSubmitInfo(.{ .all_graphics_bit = true }, current.render_finished);
        var cmd_info: vk.CommandBufferSubmitInfo = .{ .command_buffer = cmdbuf, .device_mask = 0 };
        const submit_info = Swapchain.createSubmitInfo(&cmd_info, &wait_info, &signal_info);

        // submit command buffer to the queue and execute it.
        // current.frame_fence will now block until the graphic commands finish execution
        try engine.ctx.device.queueSubmit2(
            engine.ctx.graphics_queue.handle,
            &[_]vk.SubmitInfo2{submit_info},
            current.frame_fence,
        );

        // Step 3: Present the current frame
        // this will put the image we just rendered to into the visible window.
        // we want to wait on the current.render_finished semaphore for that,
        // as its necessary that drawing commands have finished before the image is displayed to the user
        const queue_result = try engine.ctx.device.queuePresentKHR(engine.ctx.present_queue.handle, &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&self.image_index),
        });

        if (queue_result == .error_out_of_date_khr) {
            self.resize_requested = true;
        }

        // Step 4: Acquire next frame
        const result = engine.ctx.device.acquireNextImageKHR(
            self.handle,
            std.math.maxInt(u64),
            self.next_image_acquired,
            .null_handle,
        ) catch |err| {
            if (err == error.OutOfDateKHR) {
                self.resize_requested = true;
            }
            return err;
        };

        std.mem.swap(vk.Semaphore, &self.frames[result.image_index].swap_image.image_acquired, &self.next_image_acquired);
        self.image_index = result.image_index;

        return switch (result.result) {
            .success => .optimal,
            .suboptimal_khr => .suboptimal,
            else => unreachable,
        };
    }

    pub fn createSemaphoreSubmitInfo(stage_mask: vk.PipelineStageFlags2, semaphore: vk.Semaphore) vk.SemaphoreSubmitInfo {
        return .{ .device_index = 0, .semaphore = semaphore, .stage_mask = stage_mask, .value = 1 };
    }

    pub fn createSubmitInfo(cmd: *vk.CommandBufferSubmitInfo, wait_semaphore: *vk.SemaphoreSubmitInfo, signal_semaphore: *vk.SemaphoreSubmitInfo) vk.SubmitInfo2 {
        return .{
            .wait_semaphore_info_count = 1,
            .p_wait_semaphore_infos = @ptrCast(wait_semaphore),
            .command_buffer_info_count = 1,
            .p_command_buffer_infos = @ptrCast(cmd),
            .signal_semaphore_info_count = 1,
            .p_signal_semaphore_infos = @ptrCast(signal_semaphore),
        };
    }

    pub fn isRecreateNeeded(self: *Swapchain, cur_window_size: vk.Extent2D) bool {
        return cur_window_size.width != self.extent.width or cur_window_size.height != self.extent.height or self.resize_requested;
    }
};

fn findSurfaceFormat(engine: *Engine, allocator: Allocator) !vk.SurfaceFormatKHR {
    const preferred = vk.SurfaceFormatKHR{
        // .format = .r16g16b16a16_sfloat,
        .format = .r8g8b8a8_unorm,
        .color_space = .srgb_nonlinear_khr,
    };

    const surface_formats = try engine.ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(engine.ctx.physical_device, engine.ctx.surface, allocator);
    defer allocator.free(surface_formats);

    for (surface_formats) |sfmt| {
        if (std.meta.eql(sfmt, preferred)) {
            return preferred;
        }
    }

    return surface_formats[0]; // There must always be at least one supported surface format
}

fn findPresentMode(engine: *Engine, allocator: Allocator) !vk.PresentModeKHR {
    const present_modes = try engine.ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(engine.ctx.physical_device, engine.ctx.surface, allocator);
    defer allocator.free(present_modes);

    const preferred = [_]vk.PresentModeKHR{
        .mailbox_khr,
        .immediate_khr,
    };

    for (preferred) |mode| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, mode) != null) {
            return mode;
        }
    }

    return .fifo_khr;
}

fn findActualExtent(caps: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) vk.Extent2D {
    if (caps.current_extent.width != 0xFFFF_FFFF) {
        return caps.current_extent;
    } else {
        return .{
            .width = std.math.clamp(extent.width, caps.min_image_extent.width, caps.max_image_extent.width),
            .height = std.math.clamp(extent.height, caps.min_image_extent.height, caps.max_image_extent.height),
        };
    }
}
