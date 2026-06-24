// The Image Vulkan implementation
const std = @import("std");
const vk = @import("vulkan");
const sdl = @import("sdl3");

const log = std.log.scoped(.image);
const GraphicsContext = @import("../../core/graphics_context.zig");
const Buffer = @import("buffer.zig");
const Sampler = @import("sampler.zig");
const Engine = @import("engine.zig");
const CommandPool = @import("command_pool.zig");
const Primitive = @import("../../primitive.zig");

const Image = @This();

pub const ImageFormat = enum {
    jpg,
    png,
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
view: vk.ImageView,
format: vk.Format,
dimension: vk.Extent3D,
size: usize = 0,
mip_levels: u32 = 1,

pub fn create(
    engine: *Engine,
    size: vk.Extent3D,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
    is_mipmapped: bool,
) !Image {
    const mip_levels = if (is_mipmapped) calculateMipLevels(size.width, size.height) else 1;

    const image_info = vk.ImageCreateInfo{
        .flags = .{},
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
        .image_type = .@"2d",
        .extent = size,
        .mip_levels = mip_levels,
        .array_layers = 1,
        .format = format,
        .tiling = .optimal,
        .initial_layout = .undefined,
        .usage = usage,
        .samples = .{ .@"1_bit" = true },
        .sharing_mode = .exclusive,
    };
    const vk_image = try engine.ctx.device.createImage(&image_info, null);

    const mem_requirements = engine.ctx.device.getImageMemoryRequirements(vk_image);
    var alloc_info = try engine.ctx.createMemoryAllocateInfo(mem_requirements, .{ .device_local_bit = true }, false);

    const image_memory = try engine.ctx.device.allocateMemory(&alloc_info, null);
    try engine.ctx.device.bindImageMemory(vk_image, image_memory, 0);

    var aspect_flag: vk.ImageAspectFlags = .{ .color_bit = true };
    if (format == .d32_sfloat) {
        aspect_flag = .{ .depth_bit = true };
    }

    const view_info = vk.ImageViewCreateInfo{
        .image = vk_image,
        .view_type = .@"2d",
        .format = format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = aspect_flag,
            .base_mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
            .level_count = mip_levels,
        },
    };
    // Must be call after ctx.device.bindImageMemory(vk_image, image_memory, 0);
    const view = try engine.ctx.device.createImageView(&view_info, null);

    return .{
        .vk_image = vk_image,
        .vk_image_memory = image_memory,
        .view = view,
        .dimension = size,
        .format = format,
        .mip_levels = mip_levels,
        // .size = extent.width * extent.height *
    };
}

pub fn createFromSurface(
    engine: *Engine,
    surface: sdl.surface.Surface,
    usage: vk.ImageUsageFlags,
) !Image {
    var _usage = usage;
    _usage.transfer_src_bit = true;
    _usage.transfer_dst_bit = true;

    return Image.createFromBytes(
        engine,
        surface.getPixels().?,
        .{ .width = @intCast(surface.getWidth()), .height = @intCast(surface.getHeight()), .depth = 1 },
        toVulkanFormat(surface.getFormat().?),
        _usage,
        true,
    );
}

pub fn createFromPath(
    engine: *Engine,
    path: []const u8,
    pixel_format: sdl.pixels.Format,
    usage: vk.ImageUsageFlags,
) !Image {
    const surface = try loadImageAsset(path, pixel_format);
    return try Image.createFromSurface(engine, surface, usage);
}

pub fn createFromColor(
    engine: *Engine,
    color: Primitive.Color,
    size: vk.Extent3D,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
) !Image {
    var _usage = usage;
    _usage.transfer_src_bit = true;
    _usage.transfer_dst_bit = true;

    return Image.createFromBytes(
        engine,
        &color.toBytes(),
        size,
        format,
        _usage,
        false,
    );
}

pub fn createFromBytes(
    engine: *Engine,
    data: []const u8,
    size: vk.Extent3D,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
    is_mipmapped: bool,
) !Image {
    var _usage = usage;
    _usage.transfer_src_bit = true;
    _usage.transfer_dst_bit = true;

    var image = try create(engine, size, format, _usage, is_mipmapped);
    // image.size = size.width * size.height;
    image.size = data.len;

    var cmd = try TransferToGpuCmd.create(engine, &image, data, is_mipmapped);
    defer cmd.destroy();
    try engine.immediateSubmit(.graphic, &.{cmd.interface()});

    return image;
}

pub fn createFromBytesWithSDL(
    engine: *Engine,
    data: []const u8,
    usage: vk.ImageUsageFlags,
) !Image {
    const stream = try sdl.io_stream.Stream.initFromConstMem(data);
    const surface = sdl.image.loadIo(stream, true) catch |err| {
        log.err("{}, {?s}", .{ err, sdl.errors.get() });
        @panic("Image.createFromBytes");
    };
    defer surface.deinit();
    const surface_rgba = try surface.convertFormat(.array_rgba_32);
    defer surface_rgba.deinit();
    return Image.createFromSurface(engine, surface_rgba, usage);
}

pub fn destroy(self: *Image, ctx: *const GraphicsContext) void {
    ctx.device.destroyImage(self.vk_image, null);
    ctx.device.freeMemory(self.vk_image_memory, null);
    ctx.device.destroyImageView(self.view, null);
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
        .png => try sdl.image.loadPngIo(stream),
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

fn calculateMipLevels(width: u32, height: u32) u32 {
    return std.math.log2(@max(width, height)) + 1;
}

fn generateMipmaps(
    image: *const Image,
    engine: *Engine,
) void {
    const mip_levels = calculateMipLevels(image.dimension.width, image.dimension.height);
    var mip_width: u32 = @intCast(image.dimension.width);
    var mip_height: u32 = @intCast(image.dimension.height);

    for (0..mip_levels) |i| {
        const mip: u32 = @intCast(i);

        const half_size: vk.Extent3D = .{
            .width = @max(mip_width / 2, 1),
            .height = @max(mip_height / 2, 1),
            .depth = 1,
        };

        vkTransitionToLayout(engine, image.vk_image, .transfer_dst_optimal, .transfer_src_optimal, mip);

        if (mip < mip_levels - 1) {
            const blit = vk.ImageBlit2{
                .src_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_array_layer = 0,
                    .layer_count = 1,
                    .mip_level = mip,
                },
                .src_offsets = .{
                    .{ .x = 0, .y = 0, .z = 0 },
                    .{ .x = @intCast(mip_width), .y = @intCast(mip_height), .z = 1 },
                },
                .dst_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_array_layer = 0,
                    .layer_count = 1,
                    .mip_level = mip + 1,
                },
                .dst_offsets = .{
                    .{ .x = 0, .y = 0, .z = 0 },
                    .{ .x = @intCast(half_size.width), .y = @intCast(half_size.height), .z = 1 },
                },
            };

            engine.ctx.device.cmdBlitImage2(engine.getCurrentFrame().cmd_buf, &.{
                .src_image = image.vk_image,
                .src_image_layout = .transfer_src_optimal,
                .dst_image = image.vk_image,
                .dst_image_layout = .transfer_dst_optimal,
                .filter = .linear,
                .region_count = 1,
                .p_regions = @ptrCast(&blit),
            });

            mip_width = half_size.width;
            mip_height = half_size.height;
        }
    }

    // transition all mip levels into the final read_only layout
    image.transitionToLayout(engine, .transfer_src_optimal, .shader_read_only_optimal);
}

fn toVulkanFormat(sdl_format: sdl.pixels.Format) vk.Format {
    if (sdl_format == sdl.pixels.Format.array_rgba_32) return .r8g8b8a8_unorm;

    // log.debug("Pixel Format: {}", .{sdl_format});

    return switch (sdl_format) {
        .array_rgb_24 => .r8g8b8_unorm,
        else => .undefined,
    };
}

pub fn transitionToLayout(self: *const Image, engine: *Engine, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout) void {
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

    engine.ctx.device.cmdPipelineBarrier2(engine.getCurrentFrame().cmd_buf, &dep_info);
}

pub fn vkTransitionToLayout(engine: *Engine, img: vk.Image, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout, mip_level: u32) void {
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
            .base_mip_level = mip_level,
            // .level_count = vk.REMAINING_MIP_LEVELS,
            .level_count = 1,
        },
    };

    const dep_info: vk.DependencyInfo = .{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = @ptrCast(&barrier),
    };

    engine.ctx.device.cmdPipelineBarrier2(engine.getCurrentFrame().cmd_buf, &dep_info);
}

pub fn copyToImage(self: *Image, ctx: *const GraphicsContext, cmd: vk.CommandBuffer, destination: *Image) void {
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

pub fn copyImageToImage(engine: *Engine, src_img: vk.Image, dst_img: vk.Image, src_size: vk.Extent2D, dst_size: vk.Extent2D) void {
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

    engine.ctx.device.cmdBlitImage2(engine.getCurrentFrame().cmd_buf, &blit_info);
}

pub fn createDescriptorImageInfo(self: *const Image) vk.DescriptorImageInfo {
    return .{ .image_layout = .general, .image_view = self.view, .sampler = self.sampler.vk_sampler };
}

pub const TransferToGpuCmd = struct {
    staging_buffer: Buffer,
    engine: *Engine,
    image: *const Image,
    is_mipmapped: bool,

    pub fn create(engine: *Engine, image: *const Image, data: []const u8, is_mipmapped: bool) !TransferToGpuCmd {
        var staging_buffer = try Buffer.create(
            engine.ctx,
            @intCast(data.len),
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );

        try staging_buffer.copyInto(engine.ctx, data, 0);

        return .{
            .engine = engine,
            .staging_buffer = staging_buffer,
            .image = image,
            .is_mipmapped = is_mipmapped,
        };
    }

    pub fn destroy(self: *TransferToGpuCmd) void {
        self.staging_buffer.destroy(self.engine.ctx);
    }

    pub fn execute(self: *TransferToGpuCmd, engine: *Engine) void {
        self.image.transitionToLayout(engine, .undefined, .transfer_dst_optimal);

        const copy_region: vk.BufferImageCopy = .{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_extent = self.image.dimension,
            .image_offset = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
        };

        self.engine.ctx.device.cmdCopyBufferToImage(
            engine.getCurrentFrame().cmd_buf,
            self.staging_buffer.vk_buffer,
            self.image.vk_image,
            .transfer_dst_optimal,
            &.{copy_region},
        );

        if (self.is_mipmapped) {
            self.image.generateMipmaps(engine);
        } else {
            self.image.transitionToLayout(engine, .transfer_dst_optimal, .shader_read_only_optimal);
        }
    }

    pub fn interface(self: *TransferToGpuCmd) CommandPool.GpuCommand {
        return CommandPool.GpuCommand.interface(self);
    }
};
