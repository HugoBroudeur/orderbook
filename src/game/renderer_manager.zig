const std = @import("std");
const sdl = @import("sdl3");

const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ig = @import("cimgui");
const zm = @import("zmath");

const UiManager = @import("ui_manager.zig");
const EcsManager = @import("ecs_manager.zig");
const PipelineManager = @import("pipeline_manager.zig");
const ClayManager = @import("clay_manager.zig");
const FontManager = @import("font_manager.zig");
const ShaderInfo = @import("shader_info.zig");
const Ecs = @import("ecs/ecs.zig");
const Colors = @import("colors.zig");

const RendererManager = @This();

pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const TextureType = enum { demo, atlas, swapchain };
pub const SamplerType = enum { nearest, linear };

allocator: std.mem.Allocator,

init_flags: sdl.InitFlags,
device: sdl.gpu.Device = undefined,
window: sdl.video.Window = undefined,
window_size: struct {
    width: u32 = 0,
    height: u32 = 0,
} = .{},

pipelines: std.EnumArray(DrawPassType, ?PipelineManager.GraphicPipelineInfo),
transfer_buffers: std.EnumArray(TransferBufferType, ?sdl.gpu.TransferBuffer),
vertex_buffers: std.EnumArray(DrawPassType, ?sdl.gpu.Buffer),
index_buffers: std.EnumArray(DrawPassType, ?sdl.gpu.Buffer),
textures: std.EnumArray(TextureType, ?sdl.gpu.Texture),
samplers: std.EnumArray(SamplerType, ?sdl.gpu.Sampler),

// TODO: Move to AssetManager
images: std.EnumArray(TextureType, ?sdl.surface.Surface),

command_buffer: sdl.gpu.CommandBuffer = undefined,
text_engine: sdl.ttf.GpuTextEngine = undefined,

font_manager: *FontManager = undefined,

is_minimised: bool = false,

pub fn init(allocator: std.mem.Allocator) !RendererManager {
    const init_flags: sdl.InitFlags = .{ .video = true, .gamepad = true, .audio = true };
    sdl.init(init_flags) catch |err| {
        std.log.err("Error: {?s}", .{sdl.errors.get()});
        return err;
    };

    sdl.log.setAllPriorities(.debug);

    return .{
        .allocator = allocator,
        .init_flags = init_flags,
        .pipelines = .initFill(null),
        .transfer_buffers = .initFill(null),
        .vertex_buffers = .initFill(null),
        .index_buffers = .initFill(null),
        .textures = .initFill(null),
        .samplers = .initFill(null),
        .images = .initFill(null),
    };
}

pub fn deinit(self: *RendererManager) void {
    self.device.waitForIdle() catch unreachable;
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

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
    for (self.index_buffers.values) |maybe_vbo| {
        if (maybe_vbo) |vbo| {
            self.device.releaseBuffer(vbo);
        }
    }
    for (self.vertex_buffers.values) |maybe_vbo| {
        if (maybe_vbo) |vbo| {
            self.device.releaseBuffer(vbo);
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

    sdl.quit(self.init_flags);
}

pub fn setup(
    self: *RendererManager,
    ecs_manager: *EcsManager,
    pipeline_manager: *PipelineManager,
    font_manager: *FontManager,
    window_option: struct { title: []const u8, width: i32, height: i32 },
) !void {
    self.font_manager = font_manager;

    // Create Device
    self.device = sdl.gpu.Device.init(.{ .spirv = true, .dxil = true, .metal_lib = true }, true, null) catch |err| {
        std.log.err("[RendererManager.setup] SDL Create Device: {?s}", .{sdl.errors.get()});
        return err;
    };

    // Create Window
    const window_flags: sdl.video.Window.Flags = .{ .resizable = true, .hidden = false, .high_pixel_density = true };
    const main_scale = try sdl.video.Display.getContentScale(try sdl.video.Display.getPrimaryDisplay());
    const t = try self.allocator.dupeZ(u8, window_option.title);
    defer self.allocator.free(t);

    self.window = sdl.video.Window.init(t, @intFromFloat(@as(f32, @floatFromInt(window_option.width)) * main_scale), @intFromFloat(@as(f32, @floatFromInt(window_option.height)) * main_scale), window_flags) catch |err| {
        std.log.err("[RendererManager.setup] SDL Window Init: {?s}", .{sdl.errors.get()});
        return err;
    };
    const icon_stream = try sdl.io_stream.Stream.initFromFile("assets/favicon.ico", .read_text);
    const window_icon = try sdl.image.loadIcoIo(icon_stream);
    try self.window.setIcon(window_icon);

    // Claim Window for the Device
    self.device.claimWindow(self.window) catch |err| {
        std.log.err("[RendererManager.setup] SDL Window Claim: {?s}", .{sdl.errors.get()});
        return err;
    };

    try self.device.setSwapchainParameters(self.window, .sdr, .vsync);
    try self.window.setPosition(
        .{ .centered = try self.window.getDisplayForWindow() },
        .{ .centered = try self.window.getDisplayForWindow() },
    );

    // Create TTF Text Engine
    self.text_engine = try sdl.ttf.GpuTextEngine.init(self.device);

    self.initImgui();

    const size = try self.window.getSize();

    ecs_manager.create_single_component_entity(Ecs.components.EnvironmentInfo, .{
        .world_time = 0,
        .window_width = @intCast(size.@"0"),
        .window_height = @intCast(size.@"1"),
    });
    ecs_manager.flush_cmd_buf();

    const format = try self.device.getSwapchainTextureFormat(self.window);

    // Setup pipelines, must be first
    self.pipelines.set(.demo, try pipeline_manager.loadDemo(format));
    self.pipelines.set(.ui, try pipeline_manager.loadUi(format));

    try self.createBuffers();
    try self.createImages();
    try self.createTextures();
    try self.createSamplers();

    try self.createTransferBuffers();
    try self.sendSetupDataToGpu();
    // try self.destroyTranferBuffers();
}

fn initImgui(self: *RendererManager) void {
    _ = impl_sdl3.ImGui_ImplSDL3_InitForSDLGPU(@ptrCast(self.window.value));
    var init_info: impl_sdlgpu3.ImGui_ImplSDLGPU3_InitInfo = undefined;
    init_info.Device = @ptrCast(self.device.value);
    const texture_format = self.device.getSwapchainTextureFormat(self.window) catch unreachable;
    init_info.ColorTargetFormat = @intFromEnum(texture_format);
    init_info.MSAASamples = @intFromEnum(sdl.gpu.SampleCount.no_multisampling);
    _ = impl_sdlgpu3.ImGui_ImplSDLGPU3_Init(&init_info);
}

fn createBuffers(self: *RendererManager) !void {
    std.log.info("[RendererManager.createBuffers]", .{});
    if (self.pipelines.get(.ui)) |pipeline| {
        const vertex_buffer = try self.device.createBuffer(.{ .usage = .{ .vertex = true }, .size = pipeline.vertex_buffer_size });
        self.vertex_buffers.set(.ui, vertex_buffer);

        const index_buffer = try self.device.createBuffer(.{ .usage = .{ .index = true }, .size = pipeline.vertex_buffer_size });
        self.index_buffers.set(.ui, index_buffer);
    }
}

fn createTransferBuffers(self: *RendererManager) !void {
    std.log.info("[RendererManager.createTransferBuffers]", .{});
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
fn createImages(self: *RendererManager) !void {
    std.log.info("[RendererManager.createImages]", .{});
    const background_stream = try sdl.io_stream.Stream.initFromFile("assets/images/Background.jpg", .read_text);
    const background_img = try sdl.image.loadJpgIo(background_stream);
    defer background_img.deinit();
    const background_img_formated = try background_img.convertFormat(.array_rgba_32);

    std.log.info("Image info: {}x{}, {} bytes", .{ background_img_formated.getWidth(), background_img_formated.getHeight(), background_img_formated.getPixels().?.len });
    std.log.info("Pixel format: {}", .{background_img_formated.getFormat().?});
    std.log.info("Expected: {} bytes", .{background_img_formated.getWidth() * background_img_formated.getHeight() * 4});
    self.images.set(.atlas, background_img_formated);
}

fn createTextures(self: *RendererManager) !void {
    std.log.info("[RendererManager.createTextures]", .{});
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

fn createSamplers(self: *RendererManager) !void {
    std.log.info("[RendererManager.createSamplers]", .{});

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

fn sendSetupDataToGpu(self: *RendererManager) !void {
    std.log.info("[RendererManager.sendSetupDataToGpu]", .{});

    // Set up Buffer Data
    if (self.transfer_buffers.get(.atlas_buffer_data)) |tbo| {
        const gpu_tb_ptr = try self.device.mapTransferBuffer(tbo, false);
        defer self.device.unmapTransferBuffer(tbo);

        const vertices = [4]ShaderInfo.PositionTextureVertex{
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
        std.log.err("[RendererManager.sendSetupDataToGpu] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.command_buffer.submit() catch {
            std.log.err("[RendererManager.sendSetupDataToGpu] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    {
        const copy_pass = self.command_buffer.beginCopyPass();
        defer copy_pass.end();

        if (self.transfer_buffers.get(.atlas_buffer_data)) |tbo| {
            if (self.pipelines.get(.ui)) |pipeline| {
                if (self.vertex_buffers.get(.ui)) |vbo| {
                    copy_pass.uploadToBuffer(.{ .transfer_buffer = tbo, .offset = 0 }, .{
                        .buffer = vbo,
                        .offset = 0,
                        // TODO: Vertex Buffer should have more info
                        .size = pipeline.vertex_buffer_size,
                    }, false);
                }
                if (self.index_buffers.get(.ui)) |ibo| {
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

fn destroyTranferBuffers(self: *RendererManager) !void {
    for (&self.transfer_buffers.values) |*maybe_tbo| {
        if (maybe_tbo.*) |tbo| {
            self.device.releaseTransferBuffer(tbo);
            maybe_tbo.* = null;
        }
    }
}

pub fn startFrame(self: *RendererManager) void {
    Ecs.logger.info("[RendererManager.startFrame]", .{});
    _ = self;

    // Mandatory start a Imgui frame binding
    impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
    impl_sdl3.ImGui_ImplSDL3_NewFrame();
}

pub fn drawFrame(self: *RendererManager, draw_data: *Ecs.components.Graphics.DrawData) void {
    Ecs.logger.info("[RendererManager.drawFrame]", .{});

    self.is_minimised = (draw_data.ui.*.DisplaySize.x <= 0.0) or (draw_data.ui.*.DisplaySize.y <= 0.0);

    self.command_buffer = self.device.acquireCommandBuffer() catch {
        std.log.err("[RendererManager.drawFrame] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.command_buffer.submit() catch {
            std.log.err("[RendererManager.drawFrame] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    const swapchain_image = self.command_buffer.waitAndAcquireSwapchainTexture(self.window) catch {
        std.log.err("[RendererManager.drawFrame] {?s}", .{sdl.errors.get()});
        self.command_buffer.cancel() catch {};
        return;
    };

    // if (swapchain_image.@"1" != self.window.getSize())

    if (swapchain_image.@"0") |texture| {
        self.textures.set(.swapchain, texture);

        self.drawDemo();
        self.drawUi(draw_data);
    }
}

fn drawDemo(self: *RendererManager) void {
    if (self.textures.get(.swapchain)) |texture| {
        const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
            .load = .clear,
            .store = .store,
            .clear_color = Colors.Teal.toSdl(),
            .texture = texture,
        };

        // Setup and start a render pass
        const render_pass = self.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
        defer render_pass.end();

        if (self.pipelines.get(.demo)) |pipeline_info| {
            render_pass.bindGraphicsPipeline(pipeline_info.pipeline);
            // TODO viewport
            // TODO scisor
        }

        render_pass.drawPrimitives(3, 1, 0, 0);
    }
}

fn drawUi(self: *RendererManager, draw_data: *Ecs.components.Graphics.DrawData) void {
    if (self.textures.get(.swapchain)) |swapchain_texture| {
        const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
            .store = .store,
            .texture = swapchain_texture,
        };

        impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data.ui), @ptrCast(self.command_buffer.value));

        // Setup and start a render pass
        const render_pass = self.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
        defer render_pass.end();

        ClayManager.renderCommands(draw_data.clay_render_cmds);

        if (self.pipelines.get(.ui)) |pipeline_info| {
            render_pass.bindGraphicsPipeline(pipeline_info.pipeline);
            // TODO viewport
            // TODO scisor
            render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.vertex_buffers.get(.ui).?, .offset = 0 }});
            render_pass.bindIndexBuffer(.{ .buffer = self.index_buffers.get(.ui).?, .offset = 0 }, .indices_16bit);
            render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.textures.get(.atlas).?, .sampler = self.samplers.get(.nearest).? }});

            render_pass.drawIndexedPrimitives(6, 1, 0, 0, 0);
        }

        if (!self.is_minimised) {
            // Render ImGui
            impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(draw_data.ui), @ptrCast(self.command_buffer.value), @ptrCast(render_pass.value), null);
        }
    }
}

// pub fn endFrame(self: *RendererManager) void {
//     Ecs.logger.info("[RendererManager.endFrame]", .{});
//
//     // //
//     // if (self.gpu_device.window.show_delay >= 0) {
//     //     self.gpu_device.window.show_delay -= 1;
//     // }
//     // if (self.gpu_device.window.show_delay == 0) { // Visible main window here at start up
//     //     _ = sdl.SDL_ShowWindow(self.gpu_device.window.window);
//     // }
// }
