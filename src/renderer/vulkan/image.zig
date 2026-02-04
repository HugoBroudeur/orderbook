// The Image Vulkan implementation
const std = @import("std");
const vk = @import("vulkan");
const sdl = @import("sdl3");

const log = std.log.scoped(.image);
const GraphicsContext = @import("../../core/graphics_context.zig");
const Buffer = @import("buffer.zig");
const Sampler = @import("sampler.zig");

const Image = @This();

pub const ImageFormat = enum {
    jpg,
    pub fn fromExtension(extension: []const u8) ?ImageFormat {
        // var ext = std.fs.path.extension(extension);
        var ext = extension;
        if (ext.len > 0) {
            ext = ext[1..];
        }

        return std.meta.stringToEnum(ImageFormat, ext);
    }
};

vk_image: vk.Image,
vk_image_memory: vk.DeviceMemory,
vk_memory_property: vk.MemoryPropertyFlags,
sampler: Sampler,
view: vk.ImageView,
usage: vk.ImageUsageFlags,
width: u32 = 0,
height: u32 = 0,
size: usize = 0,

pub fn create(
    ctx: *const GraphicsContext,
    usage: vk.ImageUsageFlags,
    properties: vk.MemoryPropertyFlags,
    extent: vk.Extent3D,
    format: vk.Format,
) !Image {
    log.debug("Create from image. usage {f} properties {f}", .{ usage, properties });

    const image_info = vk.ImageCreateInfo{
        .flags = .{},
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
        .image_type = .@"2d",
        .extent = extent,
        .mip_levels = 1,
        .array_layers = 1,
        .format = format,
        .tiling = .optimal,
        .initial_layout = .undefined,
        .usage = usage,
        .samples = .{ .@"1_bit" = true },
        .sharing_mode = .exclusive,
    };
    const vk_image = try ctx.device.createImage(&image_info, null);

    const mem_requirements = ctx.device.getImageMemoryRequirements(vk_image);
    var alloc_info = try ctx.createMemoryAllocateInfo(mem_requirements, properties, false);

    const image_memory = try ctx.device.allocateMemory(&alloc_info, null);
    try ctx.device.bindImageMemory(vk_image, image_memory, 0);

    const view_info = vk.ImageViewCreateInfo{
        .image = vk_image,
        .view_type = .@"2d",
        .format = format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
            .level_count = 1,
        },
    };
    // Must be call after ctx.device.bindImageMemory(vk_image, image_memory, 0);
    const view = try ctx.device.createImageView(&view_info, null);

    const sampler = try Sampler.create(ctx, .linear);

    return .{
        .vk_image = vk_image,
        .vk_image_memory = image_memory,
        .vk_memory_property = properties,
        .sampler = sampler,
        .view = view,
        .usage = usage,
        .width = extent.width,
        .height = extent.height,
        // .size = extent.width * extent.height *
    };
}

pub fn createFromSurface(
    ctx: *const GraphicsContext,
    surface: sdl.surface.Surface,
    usage: vk.ImageUsageFlags,
    properties: vk.MemoryPropertyFlags,
) !Image {
    var image = try create(
        ctx,
        usage,
        properties,
        .{ .width = @intCast(surface.getWidth()), .height = @intCast(surface.getHeight()), .depth = 1 },
        toVulkanFormat(surface.getFormat().?),
    );

    image.size = surface.getPixels().?.len;

    return image;
}

pub fn destroy(self: *Image, ctx: *const GraphicsContext) void {
    ctx.device.destroyImage(self.vk_image, null);
    ctx.device.freeMemory(self.vk_image_memory, null);
    ctx.device.destroyImageView(self.view, null);
    self.sampler.destroy(ctx);
}

pub fn upload(self: *Image, copy_pass: sdl.gpu.CopyPass, tb: Buffer.TransferBuffer) void {
    copy_pass.uploadToTexture(.{ .transfer_buffer = tb.ptr, .offset = 0 }, .{
        .texture = self.ptr,
        .width = @intCast(self.surface.?.getWidth()),
        .height = @intCast(self.surface.?.getHeight()),
        .depth = 1,
    }, false);
}

pub fn bind(self: *Image, render_pass: sdl.gpu.RenderPass, sampler: Sampler) void {
    render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.ptr, .sampler = sampler.ptr }});
}

pub fn loadImageAsset(image_path: []const u8, pixel_format: sdl.pixels.Format) !sdl.surface.Surface {
    const extension = std.fs.path.extension(image_path);
    const format = ImageFormat.fromExtension(extension);
    if (format == null) {
        log.err("Can't load image. Extension {s} not supported", .{extension});
        return error.ImageExtNotSupported;
    }

    var buf: [256:0]u8 = undefined;
    const len = image_path.len;

    std.mem.copyForwards(u8, buf[0..len], image_path);
    buf[len] = 0;

    const slice = buf[0..len :0];
    const stream = try sdl.io_stream.Stream.initFromFile(slice, .read_text);

    const surface = switch (format.?) {
        .jpg => try sdl.image.loadJpgIo(stream),
    };
    defer surface.deinit();

    const surface_formated = try surface.convertFormat(pixel_format);

    log.info(
        \\====== Asset image loaded =====
        \\  Path         : {s}
        \\  Dimension    : {}x{}
        \\  Size         : {} bytes
        \\  Extension    : {s}
        \\  Pixel format : {}
        \\
    , .{
        image_path,
        surface_formated.getWidth(),
        surface_formated.getHeight(),
        surface_formated.getPixels().?.len,
        extension,
        surface_formated.getFormat().?,
    });

    return surface_formated;
}

fn toVulkanFormat(sdl_format: sdl.pixels.Format) vk.Format {
    if (sdl_format == sdl.pixels.Format.array_rgba_32) return .r8g8b8a8_unorm;

    return switch (sdl_format) {
        else => .undefined,
    };
}

pub fn transitionToLayout(self: *Image, ctx: *GraphicsContext, cmd: vk.CommandBuffer, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout) void {
    const aspect_mask: vk.ImageAspectFlags = if (new_layout == .depth_attachment_optimal) .{ .depth_bit = true } else .{ .color_bit = true };

    const barrier: vk.ImageMemoryBarrier2 = .{
        .src_stage_mask = .{ .all_commands_bit = true },
        .src_access_mask = .{ .memory_write_bit = true },
        .dst_stage_mask = .{ .all_commands_bit = true },
        .dst_access_mask = .{ .memory_write_bit = true, .memory_read_bit = true },
        .old_layout = old_layout,
        .new_layout = new_layout,
        .image = self.vk_image,
        .src_queue_family_index = 0,
        .dst_queue_family_index = 0,
        .subresource_range = .{
            .aspect_mask = aspect_mask,
            .base_array_layer = 0,
            .layer_count = vk.REMAINING_ARRAY_LAYERS,
            .base_mip_level = 0,
            .level_count = vk.REMAINING_MIP_LEVELS,
        },
    };

    const dep_info: vk.DependencyInfo = .{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = @ptrCast(&barrier),
    };

    ctx.device.cmdPipelineBarrier2(cmd, &dep_info);
}

pub fn vkTransitionToLayout(img: vk.Image, ctx: *GraphicsContext, cmd: vk.CommandBuffer, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout) void {
    const aspect_mask: vk.ImageAspectFlags = if (new_layout == .depth_attachment_optimal) .{ .depth_bit = true } else .{ .color_bit = true };

    const barrier: vk.ImageMemoryBarrier2 = .{
        .src_stage_mask = .{ .all_commands_bit = true },
        .src_access_mask = .{ .memory_write_bit = true },
        .dst_stage_mask = .{ .all_commands_bit = true },
        .dst_access_mask = .{ .memory_write_bit = true, .memory_read_bit = true },
        .old_layout = old_layout,
        .new_layout = new_layout,
        .image = img,
        .src_queue_family_index = 0,
        .dst_queue_family_index = 0,
        .subresource_range = .{
            .aspect_mask = aspect_mask,
            .base_array_layer = 0,
            .layer_count = vk.REMAINING_ARRAY_LAYERS,
            .base_mip_level = 0,
            .level_count = vk.REMAINING_MIP_LEVELS,
        },
    };

    const dep_info: vk.DependencyInfo = .{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = @ptrCast(&barrier),
    };

    ctx.device.cmdPipelineBarrier2(cmd, &dep_info);
}

pub fn copyToImage(self: *Image, ctx: *GraphicsContext, cmd: vk.CommandBuffer, destination: *Image) void {
    const blit_region: vk.ImageBlit2 = .{
        .src_offsets = .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = self.width, .y = self.height, .z = 1 },
        },
        .dst_offsets = .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = destination.width, .y = destination.height, .z = 1 },
        },
        .src_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .layer_count = 1,
            .mip_level = 0,
        },
        .dst_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .layer_count = 1,
            .mip_level = 0,
        },
    };

    const blit_info: vk.BlitImageInfo2 = .{
        .src_image = self.vk_image,
        .src_image_layout = .transfer_src_optimal,
        .dst_image = destination.vk_image,
        .dst_image_layout = .transfer_dst_optimal,
        .filter = .linear,
        .region_count = 1,
        .p_regions = &blit_region,
    };

    ctx.device.cmdBlitImage2(cmd, &blit_info);
}

pub fn vkCopyToImage(ctx: *GraphicsContext, cmd: vk.CommandBuffer, src_img: vk.Image, dst_img: vk.Image, src_size: vk.Extent2D, dst_size: vk.Extent2D) void {
    const blit_region: vk.ImageBlit2 = .{
        .src_offsets = .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = @intCast(src_size.width), .y = @intCast(src_size.height), .z = 1 },
        },
        .dst_offsets = .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = @intCast(dst_size.width), .y = @intCast(dst_size.height), .z = 1 },
        },
        .src_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .layer_count = 1,
            .mip_level = 0,
        },
        .dst_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .base_array_layer = 0,
            .layer_count = 1,
            .mip_level = 0,
        },
    };

    const blit_info: vk.BlitImageInfo2 = .{
        .src_image = src_img,
        .src_image_layout = .transfer_src_optimal,
        .dst_image = dst_img,
        .dst_image_layout = .transfer_dst_optimal,
        .filter = .linear,
        .region_count = 1,
        .p_regions = &.{blit_region},
    };

    ctx.device.cmdBlitImage2(cmd, &blit_info);
}

pub fn createDescriptorImageInfo(self: *const Image) vk.DescriptorImageInfo {
    return .{ .image_layout = .general, .image_view = self.view, .sampler = self.sampler.vk_sampler };
}
