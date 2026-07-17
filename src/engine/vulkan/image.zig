// The Image Vulkan implementation
const std = @import("std");
const vk = @import("vulkan");
const sdl = @import("sdl3");

const log = std.log.scoped(.image);
const GraphicsContext = @import("../../core/graphics_context.zig");
const Buffer = @import("buffer.zig");
const Sampler = @import("sampler.zig");
const Engine = @import("engine.zig");
const VulkanCommand = @import("command_pool.zig");
const AllocatedCommandBuffer = VulkanCommand.AllocatedCommandBuffer;
const Primitive = @import("../../primitive.zig");

const Image = @This();

pub const Dimension = struct {
    width: u32,
    height: u32,
    depth: u32 = 0,
};

pub const ImageFormat = enum {
    jpg,
    jpeg,
    png,
    // webp,

    pub fn fromExtension(extension: []const u8) ?ImageFormat {
        // var ext = std.fs.path.extension(extension);
        var ext = extension;
        if (ext.len > 0) {
            ext = ext[1..];
        }

        return std.meta.stringToEnum(ImageFormat, ext);
    }

    pub fn fromStem(stem: []const u8) ?ImageFormat {
        return std.meta.stringToEnum(ImageFormat, stem);
    }
};

pub const DataKind = enum { path, pixels };

pub const ImageDataKind = union(DataKind) {
    path: []const u8,
    // cubemap_path: []const u8,
    pixels: struct {
        data: []const u8,
        format: sdl.pixels.Format = .array_rgba_32,
    },
};

pub const ImageMetadata = struct {
    kind: ImageDataKind,
    dimension: ?Dimension,

    pub fn init(kind: ImageDataKind, dimension: ?Dimension) ImageMetadata {
        return .{
            .kind = kind,
            .dimension = dimension,
        };
    }

    fn toSdlSurface(self: ImageMetadata) !sdl.surface.Surface {
        return switch (self.kind) {
            .path => |path| try loadFile(path),
            .pixels => |pixels| {
                if (self.dimension == null) {
                    const stream = try sdl.io_stream.Stream.initFromConstMem(pixels.data);
                    return try sdl.image.loadIo(stream, true);
                }

                return try sdl.surface.Surface.initFrom(@intCast(self.dimension.?.width), @intCast(self.dimension.?.height), pixels.format, pixels.data);
            },
        };
    }

    pub fn upload(self: ImageMetadata, engine: *Engine, allocated_image: AllocatedImage) !void {
        var surface = try self.toSdlSurface();
        surface = try surface.convertFormat(.array_rgba_32);
        defer surface.deinit();
        try allocated_image.upload(engine, surface.getPixels().?);
    }

    pub fn allocateImage(self: ImageMetadata, engine: *Engine, usage: vk.ImageUsageFlags, is_mipmapped: bool, layer_count: u32) !AllocatedImage {
        // Force the transfert bits for uploading later on
        var _usage = usage;
        _usage.transfer_src_bit = true;
        _usage.transfer_dst_bit = true;
        var surface = try self.toSdlSurface();
        surface = try surface.convertFormat(.array_rgba_32);
        defer surface.deinit();

        const dimension: Dimension = if (self.dimension) |d| d else .{ .width = @intCast(surface.getWidth()), .height = @intCast(surface.getHeight()) };
        const format: vk.Format = if (surface.getFormat()) |f| toVulkanFormat(f) else .r8g8b8a8_unorm;

        return try AllocatedImage.create(engine, dimension, format, _usage, is_mipmapped, layer_count);
    }
};

pub const AllocatedImage = struct {
    vk_image: vk.Image,
    vk_image_memory: vk.DeviceMemory,
    view: vk.ImageView,
    format: vk.Format,
    dimension: vk.Extent3D,
    size: usize = 0,
    mip_levels: u32 = 1,
    layer_count: u32 = 0,

    pub fn create(
        engine: *Engine,
        dimension: Dimension,
        format: vk.Format,
        usage: vk.ImageUsageFlags,
        is_mipmapped: bool,
        layer_count: u32,
    ) !AllocatedImage {
        const vk_dimension: vk.Extent3D = .{ .width = dimension.width, .height = dimension.height, .depth = 1 };

        const mip_levels = if (is_mipmapped) calculateMipLevels(vk_dimension.width, vk_dimension.height) else 1;

        const image_info = vk.ImageCreateInfo{
            .flags = .{},
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
            .image_type = .@"2d",
            .extent = vk_dimension,
            .mip_levels = mip_levels,
            .array_layers = layer_count,
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
            .dimension = vk_dimension,
            .format = format,
            .mip_levels = mip_levels,
            .layer_count = layer_count,
        };
    }

    pub fn upload(self: AllocatedImage, engine: *Engine, bytes: []const u8) !void {
        var immediate_cmd = try VulkanCommand.ImmediateCommands.init(engine, engine.getCurrentFrame().cmd_pool);
        defer immediate_cmd.deinit(engine);

        var gpu_cmd = try TransferToGpuCmd.create(engine, &immediate_cmd.buffer, self, bytes);
        defer gpu_cmd.destroy();

        try immediate_cmd.addCommand(engine.allocator, gpu_cmd.interface());

        try engine.immediateSubmit(.graphic, immediate_cmd);
    }

    pub fn destroy(self: *AllocatedImage, engine: *Engine) void {
        engine.ctx.device.destroyImage(self.vk_image, null);
        engine.ctx.device.freeMemory(self.vk_image_memory, null);
        engine.ctx.device.destroyImageView(self.view, null);
    }

    pub fn transitionLayout(self: AllocatedImage, engine: *Engine, cmd_buffer: AllocatedCommandBuffer, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout, base_mip_level: u32, level_count: u32) void {
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
                .base_mip_level = base_mip_level,
                .level_count = level_count,
            },
        };

        const dep_info: vk.DependencyInfo = .{
            .image_memory_barrier_count = 1,
            .p_image_memory_barriers = @ptrCast(&barrier),
        };

        engine.ctx.device.cmdPipelineBarrier2(cmd_buffer.vk_command_buffer, &dep_info);
    }

    pub fn copyTo(self: AllocatedImage, engine: *Engine, cmd_buffer: AllocatedCommandBuffer, dst_img: AllocatedImage) void {
        const blit_region: vk.ImageBlit2 = .{
            .src_offsets = .{
                .{ .x = 0, .y = 0, .z = 0 },
                .{ .x = @intCast(self.dimension.width), .y = @intCast(self.dimension.height), .z = 1 },
            },
            .dst_offsets = .{
                .{ .x = 0, .y = 0, .z = 0 },
                .{ .x = @intCast(dst_img.dimension.width), .y = @intCast(dst_img.dimension.height), .z = 1 },
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
            .dst_image = dst_img.vk_image,
            .dst_image_layout = .transfer_dst_optimal,
            .filter = .linear,
            .region_count = 1,
            .p_regions = &.{blit_region},
        };

        engine.ctx.device.cmdBlitImage2(cmd_buffer.vk_command_buffer, &blit_info);
    }

    fn generateMipmaps(
        self: *const AllocatedImage,
        engine: *Engine,
        cmd_buffer: AllocatedCommandBuffer,
    ) void {
        const mip_levels = calculateMipLevels(self.dimension.width, self.dimension.height);
        var mip_width: u32 = @intCast(self.dimension.width);
        var mip_height: u32 = @intCast(self.dimension.height);

        for (0..mip_levels) |i| {
            const mip: u32 = @intCast(i);

            const half_size: vk.Extent3D = .{
                .width = @max(mip_width / 2, 1),
                .height = @max(mip_height / 2, 1),
                .depth = 1,
            };

            self.transitionLayout(engine, cmd_buffer, .transfer_dst_optimal, .transfer_src_optimal, mip, 1);

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

                engine.ctx.device.cmdBlitImage2(cmd_buffer.vk_command_buffer, &.{
                    .src_image = self.vk_image,
                    .src_image_layout = .transfer_src_optimal,
                    .dst_image = self.vk_image,
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
        self.transitionLayout(engine, cmd_buffer, .transfer_src_optimal, .shader_read_only_optimal, 0, mip_levels);
    }
};

pub fn createCubemapFromPath(
    engine: *Engine,
    faces: struct {
        px: []const u8,
        nx: []const u8,
        py: []const u8,
        ny: []const u8,
        pz: []const u8,
        nz: []const u8,
    },
    format: vk.Format,
    usage: vk.ImageUsageFlags,
    is_mipmapped: bool,
) !Image {
    const px = try loadImageAssetWithFormat(faces.px, .array_rgba_32);
    defer px.deinit();
    const nx = try loadImageAssetWithFormat(faces.nx, .array_rgba_32);
    defer nx.deinit();
    const py = try loadImageAssetWithFormat(faces.py, .array_rgba_32);
    defer py.deinit();
    const ny = try loadImageAssetWithFormat(faces.ny, .array_rgba_32);
    defer ny.deinit();
    const pz = try loadImageAssetWithFormat(faces.pz, .array_rgba_32);
    defer pz.deinit();
    const nz = try loadImageAssetWithFormat(faces.nz, .array_rgba_32);
    defer nz.deinit();

    const width = px.getWidth();
    const height = px.getHeight();

    const dimension: vk.Extent3D = .{ .width = width, .height = height, .depth = 1 };
    const face_size: usize = @as(usize, height) * @as(usize, width) * 4; // 4 bytes/pixel (rgba32)

    const data = try engine.allocator.alloc(u8, face_size * 6);
    defer engine.allocator.free(data);

    // All six faces must share the same dimensions — the image is created
    // once with a single width/height for all layers, and the per-face
    // byte offsets below assume every face contributes an equal-sized slice.
    const surfaces = [_]sdl.surface.Surface{ px, nx, py, ny, pz, nz };
    const face_paths = [_][]const u8{ faces.px, faces.nx, faces.py, faces.ny, faces.pz, faces.nz };
    for (surfaces, face_paths, 0) |surface, path, i| {
        if (surface.getWidth() != width or surface.getHeight() != height) {
            log.err(
                "createCubemapFromPath: face dimension mismatch — '{s}' is {}x{}, expected {}x{} (from '{s}')",
                .{ path, surface.getWidth(), surface.getHeight(), width, height, faces.px },
            );
            return error.CubemapFaceDimensionMismatch;
        }

        const pixels = surface.getPixels().?;
        @memcpy(data[i * face_size ..][0..face_size], pixels[0..face_size]);
    }

    const image = try Image.create(engine, dimension, format, usage, is_mipmapped, 6);

    var immediate_cmd = try VulkanCommand.ImmediateCommands.init(engine, engine.getCurrentFrame().cmd_pool);
    defer immediate_cmd.deinit(engine);

    var gpu_cmd = try TransferToGpuCmd.create(engine, &immediate_cmd.buffer, &image, data, is_mipmapped, 6);
    defer gpu_cmd.destroy();

    try immediate_cmd.addCommand(engine.allocator, gpu_cmd.interface());

    try engine.immediateSubmit(.graphic, immediate_cmd);

    return image;
}

pub fn loadImageAssetWithFormat(image_path: []const u8, pixel_format: sdl.pixels.Format) !sdl.surface.Surface {
    const surface = try loadFile(image_path);

    const surface_formated = try surface.convertFormat(pixel_format);
    return surface_formated;
}

pub fn loadFile(image_path: []const u8) !sdl.surface.Surface {
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
        .jpg, .jpeg => try sdl.image.loadJpgIo(stream),
        .png => try sdl.image.loadPngIo(stream),
        // .webp => try sdl.image.loadWebpIo(stream),
    };
    defer surface.deinit();

    log.info(
        \\====== Image loaded =====
        \\  Path         : {s}
        \\  Dimension    : {}x{}
        \\  Size         : {} bytes
        \\  Extension    : {s}
        \\  Pixel format : {}
        \\
    , .{
        image_path,
        surface.getWidth(),
        surface.getHeight(),
        surface.getPixels().?.len,
        extension,
        surface.getFormat().?,
    });

    return surface;
}

fn calculateMipLevels(width: u32, height: u32) u32 {
    return std.math.log2(@max(width, height)) + 1;
}

fn toVulkanFormat(sdl_format: sdl.pixels.Format) vk.Format {
    if (sdl_format == sdl.pixels.Format.array_rgba_32) return .r8g8b8a8_unorm;

    // log.debug("Pixel Format: {}", .{sdl_format});

    return switch (sdl_format) {
        .array_rgb_24 => .r8g8b8a8_unorm,
        else => .undefined,
    };
}

pub const TransferToGpuCmd = struct {
    staging_buffer: Buffer,
    engine: *Engine,
    image: AllocatedImage,
    cmd_buffer: *VulkanCommand.AllocatedCommandBuffer,

    pub fn create(engine: *Engine, cmd_buffer: *VulkanCommand.AllocatedCommandBuffer, image: AllocatedImage, data: []const u8) !TransferToGpuCmd {
        var staging_buffer = try Buffer.create(
            engine,
            @intCast(data.len),
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );

        try staging_buffer.copyInto(data, 0);

        return .{
            .engine = engine,
            .staging_buffer = staging_buffer,
            .image = image,
            .cmd_buffer = cmd_buffer,
        };
    }

    pub fn destroy(self: *TransferToGpuCmd) void {
        self.staging_buffer.destroy();
    }

    pub fn execute(self: *TransferToGpuCmd, engine: *Engine) void {
        // Whole chain up front: level 0 is about to receive the buffer copy
        // below, and levels 1.. need to already be in transfer_dst_optimal
        // before generateMipmaps blits into them as destinations.
        self.image.transitionLayout(engine, self.cmd_buffer.*, .undefined, .transfer_dst_optimal, 0, self.image.mip_levels);

        var copies = std.ArrayList(vk.BufferImageCopy).initCapacity(engine.allocator, 1) catch return;
        for (0..self.image.layer_count) |layer| {
            for (0..self.image.mip_levels) |level| {
                const offset = level / self.staging_buffer.size; //TODO: This is wrong, it needs to take into account the amount of layers
                const copy_region: vk.BufferImageCopy = .{
                    .buffer_offset = @intCast(offset),
                    .buffer_row_length = 0,
                    .buffer_image_height = 0,
                    .image_subresource = .{
                        .aspect_mask = .{ .color_bit = true },
                        // .mip_level = if (self.image.mip_levels > 0) calculateMipLevels(self.image.dimension.width, self.image.dimension.height) else 0,
                        .mip_level = 0,
                        // .base_array_layer = @intCast(i),
                        .base_array_layer = @intCast(layer),
                        .layer_count = 1,
                    },
                    .image_extent = self.image.dimension,
                    .image_offset = .{
                        .x = 0,
                        .y = 0,
                        .z = 0,
                    },
                };

                copies.append(engine.allocator, copy_region) catch continue;
            }
        }

        self.engine.ctx.device.cmdCopyBufferToImage(
            self.cmd_buffer.vk_command_buffer,
            self.staging_buffer.vk_buffer,
            self.image.vk_image,
            .transfer_dst_optimal,
            copies.items,
        );

        if (self.image.mip_levels > 1) {
            self.image.generateMipmaps(engine, self.cmd_buffer.*);
        } else {
            self.image.transitionLayout(engine, self.cmd_buffer.*, .transfer_dst_optimal, .shader_read_only_optimal, 0, 1);
        }
    }

    pub fn interface(self: *TransferToGpuCmd) VulkanCommand.GpuCommand {
        return VulkanCommand.GpuCommand.interface(self);
    }
};
