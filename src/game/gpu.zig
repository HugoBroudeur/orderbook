const std = @import("std");
const sdl = @import("sdl3");
const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");

const zm = @import("zmath");

const PipelineManager = @import("pipeline_manager.zig");
const Colors = @import("colors.zig");

const GPU = @This();

pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const TextureType = enum { demo, atlas, swapchain };
pub const SamplerType = enum { nearest, linear };
pub const UniformBufferType = enum { time };
pub const BufferType = enum { index_quad, vertex_quad, uniform_time };

device: sdl.gpu.Device = undefined,
window: sdl.video.Window = undefined,

pipelines: std.EnumArray(DrawPassType, ?PipelineManager.GraphicPipelineInfo),
transfer_buffers: std.EnumArray(TransferBufferType, ?sdl.gpu.TransferBuffer),
buffers: std.EnumArray(BufferType, ?sdl.gpu.Buffer),
// vertex_buffers: std.EnumArray(DrawPassType, ?sdl.gpu.Buffer),
// index_buffers: std.EnumArray(DrawPassType, ?sdl.gpu.Buffer),
textures: std.EnumArray(TextureType, ?sdl.gpu.Texture),
samplers: std.EnumArray(SamplerType, ?sdl.gpu.Sampler),

// TODO: Move to AssetManager
images: std.EnumArray(TextureType, ?sdl.surface.Surface),

command_buffer: sdl.gpu.CommandBuffer = undefined,
text_engine: sdl.ttf.GpuTextEngine = undefined,
pipeline_manager: PipelineManager,

pub fn init(allocator: std.mem.Allocator) !GPU {
    // Create Device
    var device = try sdl.gpu.Device.init(.{ .spirv = true, .dxil = true, .metal_lib = true }, true, null);

    // Create Window
    const window_flags: sdl.video.Window.Flags = .{ .resizable = true, .hidden = false, .high_pixel_density = true };

    const window = try sdl.video.Window.init("", 0, 0, window_flags);

    // Claim Window for the Device
    try device.claimWindow(window);

    try device.setSwapchainParameters(window, .sdr, .vsync);
    try window.setPosition(
        .{ .centered = try window.getDisplayForWindow() },
        .{ .centered = try window.getDisplayForWindow() },
    );

    // Create TTF Text Engine
    const text_engine = try sdl.ttf.GpuTextEngine.init(device);

    var gpu = GPU{
        .device = device,
        .window = window,
        .text_engine = text_engine,
        .pipeline_manager = PipelineManager.init(allocator, &device),
        .pipelines = .initFill(null),
        .transfer_buffers = .initFill(null),
        .buffers = .initFill(null),
        .textures = .initFill(null),
        .samplers = .initFill(null),
        .images = .initFill(null),
    };

    try gpu.createPipelines();
    try gpu.createBuffers();
    try gpu.createImages();
    try gpu.createTextures();
    try gpu.createSamplers();

    try gpu.createTransferBuffers();
    try gpu.uploadTextureToGPU();

    return gpu;
}

pub fn deinit(self: *GPU) void {
    self.pipeline_manager.deinit();
    self.device.waitForIdle() catch unreachable;

    for (self.transfer_buffers.values) |maybe_tbo| {
        if (maybe_tbo) |tbo| {
            self.device.releaseTransferBuffer(tbo);
        }
    }
    for (self.pipelines.values) |pipeline| {
        if (pipeline) |p| {
            self.device.releaseGraphicsPipeline(p.pipeline);
        }
    }
    for (self.buffers.values) |maybe_buffer| {
        if (maybe_buffer) |buffer| {
            self.device.releaseBuffer(buffer);
        }
    }
    // TODO: should be destroyed but it creates a memory leak
    // for (self.textures.values) |maybe_texture| {
    //     if (maybe_texture) |texture| {
    //         self.device.releaseTexture(texture);
    //     }
    // }
    for (self.samplers.values) |maybe_sampler| {
        if (maybe_sampler) |sampler| {
            self.device.releaseSampler(sampler);
        }
    }
    for (self.images.values) |maybe_image| {
        if (maybe_image) |image| {
            image.deinit();
        }
    }

    self.text_engine.deinit();

    self.device.releaseWindow(self.window);
    self.device.deinit();
}

fn createPipelines(self: *GPU) !void {
    // Setup all resources
    const format = try self.device.getSwapchainTextureFormat(self.window);
    {
        const pipeline = try self.pipeline_manager.loadDemo(format);
        self.pipelines.set(.demo, pipeline);
    }
    {
        const pipeline = try self.pipeline_manager.loadUi(format);
        self.pipelines.set(.ui, pipeline);
    }
}

fn createBuffers(self: *GPU) !void {
    std.log.info("[GPU.createBuffers]", .{});
    if (self.pipelines.get(.ui)) |pipeline| {
        {
            const buffer = try self.device.createBuffer(.{ .usage = .{ .vertex = true }, .size = pipeline.vertex_buffer_size });
            self.buffers.set(.vertex_quad, buffer);
        }

        {
            const buffer = try self.device.createBuffer(.{ .usage = .{ .index = true }, .size = pipeline.vertex_buffer_size });
            self.buffers.set(.index_quad, buffer);
        }
    }

    {
        const buffer = try self.device.createBuffer(.{ .usage = .{ .graphics_storage_read = true }, .size = @sizeOf(f32) });
        self.buffers.set(.uniform_time, buffer);
    }
}

fn createTransferBuffers(self: *GPU) !void {
    std.log.info("[GPU.createTransferBuffers]", .{});
    if (self.pipelines.get(.ui)) |pipeline| {
        const data_transfer_buffer = try self.device.createTransferBuffer(.{
            .usage = .upload,
            .size = pipeline.index_buffer_size + pipeline.vertex_buffer_size,
        });
        self.transfer_buffers.set(.atlas_buffer_data, data_transfer_buffer);
    }

    if (self.images.get(.atlas)) |img| {
        // const img_size_bytes: usize = img.getWidth() * img.getHeight() * 4; //4 channels: r,g,b,a
        const texture_transfer_buffer = try self.device.createTransferBuffer(.{
            .usage = .upload,
            .size = @intCast(img.getPixels().?.len),
        });
        self.transfer_buffers.set(.atlas_texture_data, texture_transfer_buffer);
    }
}

// TODO: Load assets Should be in an asset manager
// TODO: Create an atlas and an atlas_texture instead
// Images must be stored with Format .packed_rgba_8_8_8_8
fn createImages(self: *GPU) !void {
    std.log.info("[GPU.createImages]", .{});
    const background_stream = try sdl.io_stream.Stream.initFromFile("assets/images/Background.jpg", .read_text);
    const background_img = try sdl.image.loadJpgIo(background_stream);
    defer background_img.deinit();
    const background_img_formated = try background_img.convertFormat(.array_rgba_32);

    std.log.info("Image info: {}x{}, {} bytes", .{ background_img_formated.getWidth(), background_img_formated.getHeight(), background_img_formated.getPixels().?.len });
    std.log.info("Pixel format: {}", .{background_img_formated.getFormat().?});
    std.log.info("Expected: {} bytes", .{background_img_formated.getWidth() * background_img_formated.getHeight() * 4});
    self.images.set(.atlas, background_img_formated);
}

fn createTextures(self: *GPU) !void {
    std.log.info("[GPU.createTextures]", .{});
    // UI Background

    if (self.images.get(.atlas)) |img| {
        const atlas_texture = try self.device.createTexture(.{
            .format = .r8g8b8a8_unorm,
            // .format = .b8g8r8a8_unorm,
            .texture_type = .two_dimensional_array,
            .width = @intCast(img.getWidth()),
            .height = @intCast(img.getHeight()),
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .usage = .{ .sampler = true },
        });
        self.textures.set(.atlas, atlas_texture);
    }
}

fn createSamplers(self: *GPU) !void {
    std.log.info("[GPU.createSamplers]", .{});

    // Nearest
    {
        const sampler = try self.device.createSampler(.{
            .mipmap_mode = .nearest,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .min_filter = .nearest,
            .mag_filter = .nearest,
        });
        self.samplers.set(.nearest, sampler);
    }

    // Linear
    {
        const sampler = try self.device.createSampler(.{
            .mipmap_mode = .linear,
            .min_filter = .linear,
            .mag_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });
        self.samplers.set(.linear, sampler);
    }
}

fn uploadTextureToGPU(self: *GPU) !void {
    std.log.info("[GPU.uploadTextureToGPU]", .{});

    // Set up Buffer Data
    if (self.transfer_buffers.get(.atlas_buffer_data)) |tbo| {
        const gpu_tb_ptr = try self.device.mapTransferBuffer(tbo, false);
        defer self.device.unmapTransferBuffer(tbo);

        const vertices = [4]PipelineManager.PositionTextureVertex{
            .{ .pos = zm.f32x4(-1, 1, 0, 1), .uv = .{ .u = 0, .v = 0 } },
            .{ .pos = zm.f32x4(1, 1, 0, 1), .uv = .{ .u = 1, .v = 0 } },
            .{ .pos = zm.f32x4(1, -1, 0, 1), .uv = .{ .u = 1, .v = 1 } },
            .{ .pos = zm.f32x4(-1, -1, 0, 1), .uv = .{ .u = 0, .v = 1 } },
        };
        const indices = [6]u16{ 0, 1, 2, 0, 2, 3 };

        const vertex_bytes = @sizeOf(@TypeOf(vertices));
        const index_bytes = @sizeOf(@TypeOf(indices));

        std.mem.copyForwards(u8, gpu_tb_ptr[0..vertex_bytes], std.mem.asBytes(&vertices));
        std.mem.copyForwards(u8, gpu_tb_ptr[vertex_bytes..(vertex_bytes + index_bytes)], std.mem.asBytes(&indices));
    }

    // Set up Texture Data with detailed logging
    // if (self.transfer_buffers.get(.atlas_texture_data)) |tbo| {
    //     std.log.info("Got transfer buffer", .{});
    //
    //     const gpu_tb_ptr = try self.device.mapTransferBuffer(tbo, false);
    //     defer self.device.unmapTransferBuffer(tbo);
    //     std.log.info("Mapped transfer buffer", .{});
    //
    //     if (self.images.get(.atlas)) |img| {
    //         const pixels = img.getPixels().?;
    //         const width = img.getWidth();
    //         const height = img.getHeight();
    //
    //         std.log.info("Image info: {}x{}, {} bytes", .{ width, height, pixels.len });
    //         std.log.info("Pixel format: {}", .{img.getFormat().?});
    //         std.log.info("Expected: {} bytes", .{width * height * 4});
    //         std.log.info("First 16 bytes: [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}]", .{ pixels[0], pixels[1], pixels[2], pixels[3], pixels[4], pixels[5], pixels[6], pixels[7], pixels[8], pixels[9], pixels[10], pixels[11], pixels[12], pixels[13], pixels[14], pixels[15] });
    //
    //         @memcpy(gpu_tb_ptr[0..pixels.len], pixels);
    //
    //         std.log.info("After memcpy, first 16 bytes in GPU buffer: [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}]", .{ gpu_tb_ptr[0], gpu_tb_ptr[1], gpu_tb_ptr[2], gpu_tb_ptr[3], gpu_tb_ptr[4], gpu_tb_ptr[5], gpu_tb_ptr[6], gpu_tb_ptr[7], gpu_tb_ptr[8], gpu_tb_ptr[9], gpu_tb_ptr[10], gpu_tb_ptr[11], gpu_tb_ptr[12], gpu_tb_ptr[13], gpu_tb_ptr[14], gpu_tb_ptr[15] });
    //     } else {
    //         std.log.err("Image .atlas not found!", .{});
    //     }
    // } else {
    //     std.log.err("Transfer buffer .atlas_texture_data not found!", .{});
    // }

    // Set up Texture Data
    if (self.transfer_buffers.get(.atlas_texture_data)) |tbo| {
        const gpu_tb_ptr = try self.device.mapTransferBuffer(tbo, false);
        defer self.device.unmapTransferBuffer(tbo);

        if (self.images.get(.atlas)) |img| {
            @memcpy(gpu_tb_ptr[0..img.getPixels().?.len], img.getPixels().?);
        }
    }

    self.command_buffer = self.device.acquireCommandBuffer() catch {
        std.log.err("[GPU.sendSetupDataToGpu] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.command_buffer.submit() catch {
            std.log.err("[GPU.sendSetupDataToGpu] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    {
        const copy_pass = self.command_buffer.beginCopyPass();
        defer copy_pass.end();

        if (self.transfer_buffers.get(.atlas_buffer_data)) |tbo| {
            if (self.pipelines.get(.ui)) |pipeline| {
                if (self.buffers.get(.vertex_quad)) |vbo| {
                    copy_pass.uploadToBuffer(.{ .transfer_buffer = tbo, .offset = 0 }, .{
                        .buffer = vbo,
                        .offset = 0,
                        // TODO: Vertex Buffer should have more info
                        .size = pipeline.vertex_buffer_size,
                    }, false);
                }
                if (self.buffers.get(.index_quad)) |ibo| {
                    copy_pass.uploadToBuffer(.{ .transfer_buffer = tbo, .offset = pipeline.vertex_buffer_size }, .{
                        .buffer = ibo,
                        .offset = 0,
                        // TODO: Vertex Buffer should have more info
                        .size = pipeline.index_buffer_size,
                    }, false);
                }
            }
        }

        if (self.transfer_buffers.get(.atlas_texture_data)) |tbo| {
            if (self.textures.get(.atlas)) |texture| {
                if (self.images.get(.atlas)) |img| {
                    copy_pass.uploadToTexture(.{ .transfer_buffer = tbo, .offset = 0 }, .{
                        .texture = texture,
                        .width = @intCast(img.getWidth()),
                        .height = @intCast(img.getHeight()),
                        .depth = 1,
                    }, false);
                }
            }
        }
    }

    { // Debug
        if (self.images.get(.atlas)) |img| {
            const pixels = img.getPixels().?;
            std.log.info("Image: {}x{}, {} bytes", .{ img.getWidth(), img.getHeight(), pixels.len });

            // Check first few pixels (should NOT be all zeros)
            std.log.info("First pixel (format {}): ({}, {}, {})", .{ img.getFormat().?, pixels[0], pixels[1], pixels[2] });
            std.log.info("Pixel at 100: ({}, {}, {})", .{ pixels[300], pixels[301], pixels[302] });

            // Calculate expected size
            const expected_rgba_size = img.getWidth() * img.getHeight() * 4;
            std.log.info("Expected buffer size: {}", .{expected_rgba_size});
        }
    }
}

fn destroyTranferBuffers(self: *GPU) !void {
    for (&self.transfer_buffers.values) |*maybe_tbo| {
        if (maybe_tbo.*) |tbo| {
            self.device.releaseTransferBuffer(tbo);
            maybe_tbo.* = null;
        }
    }
}
