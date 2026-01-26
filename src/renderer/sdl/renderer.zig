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
const GPU = @import("gpu.zig");
const Ecs = @import("ecs/ecs.zig");
const Colors = @import("colors.zig");

const RendererManager = @This();

pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const TextureType = enum { demo, atlas, swapchain };
pub const SamplerType = enum { nearest, linear };
const UniformTime = struct {
    time: f32,
    // padding: [3]f32 = .{ 0, 0, 0 }, // Make it 16 bytes
};
const UniformMvp = struct {
    proj_matrix: zm.Mat,
    view_matrix: zm.Mat,
};
const Uniform2D = struct {
    scale: @Vector(2, f32),
    translate: @Vector(2, f32),
};
const Uniforms = struct {
    ui: Uniform2D,
    mvp: UniformMvp,
    time: UniformTime,
};

allocator: std.mem.Allocator,

init_flags: sdl.InitFlags,
gpu: GPU = undefined,
window_size: struct {
    width: u32 = 0,
    height: u32 = 0,
} = .{},

font_manager: *FontManager = undefined,
clay_manager: *ClayManager = undefined,

uniforms: Uniforms = undefined,

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
    };
}

pub fn deinit(self: *RendererManager) void {
    self.gpu.device.waitForIdle() catch unreachable;
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

    self.gpu.deinit();
    sdl.quit(self.init_flags);
}

pub fn setup(
    self: *RendererManager,
    font_manager: *FontManager,
    clay_manager: *ClayManager,
    window_option: struct { title: []const u8, width: i32, height: i32 },
) !void {
    self.font_manager = font_manager;
    self.clay_manager = clay_manager;

    self.gpu = GPU.init(self.allocator) catch |err| {
        std.log.err("[RendererManager.setup] {}: {?s}", .{ err, sdl.errors.get() });
        return err;
    };

    const main_scale = try sdl.video.Display.getContentScale(try sdl.video.Display.getPrimaryDisplay());
    const t = try self.allocator.dupeZ(u8, window_option.title);
    defer self.allocator.free(t);
    const icon_stream = try sdl.io_stream.Stream.initFromFile("assets/favicon.ico", .read_text);
    const window_icon = try sdl.image.loadIcoIo(icon_stream);
    defer window_icon.deinit();

    try self.gpu.window.setTitle(t);
    try self.gpu.window.setSize(@intFromFloat(@as(f32, @floatFromInt(window_option.width)) * main_scale), @intFromFloat(@as(f32, @floatFromInt(window_option.height)) * main_scale));
    try self.gpu.window.setIcon(window_icon);

    self.initImgui();

    // Setup the uniform buffers
    var width: usize = undefined;
    var heigth: usize = undefined;
    width, heigth = try self.gpu.window.getSize();
    const fov: f32 = 40;
    const near: f32 = 0.0001;
    const far: f32 = 1000;

    self.uniforms = .{
        .ui = .{
            .scale = .{ 1, 1 },
            .translate = .{ 1, 1 },
        },
        .mvp = .{
            .proj_matrix = zm.perspectiveFovRh(zm.modAngle(fov), @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(heigth)), near, far),
            // .proj_matrix = zm.identity(),
            .view_matrix = zm.identity(),
        },
        .time = .{
            .time = 0,
        },
    };
}

fn initImgui(self: *RendererManager) void {
    _ = impl_sdl3.ImGui_ImplSDL3_InitForSDLGPU(@ptrCast(self.gpu.window.value));
    var init_info: impl_sdlgpu3.ImGui_ImplSDLGPU3_InitInfo = undefined;
    init_info.Device = @ptrCast(self.gpu.device.value);
    const texture_format = self.gpu.device.getSwapchainTextureFormat(self.gpu.window) catch unreachable;
    init_info.ColorTargetFormat = @intFromEnum(texture_format);
    init_info.MSAASamples = @intFromEnum(sdl.gpu.SampleCount.no_multisampling);
    _ = impl_sdlgpu3.ImGui_ImplSDLGPU3_Init(&init_info);
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

    self.uniforms.time.time = @floatFromInt(draw_data.time / 1000); // convert to seconds

    self.gpu.command_buffer = self.gpu.device.acquireCommandBuffer() catch {
        std.log.err("[RendererManager.drawFrame] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.gpu.command_buffer.submit() catch {
            std.log.err("[RendererManager.drawFrame] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    const swapchain_image = self.gpu.command_buffer.acquireSwapchainTexture(self.gpu.window) catch {
        std.log.err("[RendererManager.drawFrame] {?s}", .{sdl.errors.get()});
        self.gpu.command_buffer.cancel() catch {};
        return;
    };

    // if (swapchain_image.@"1" != self.window.getSize())

    if (swapchain_image.@"0") |texture| {
        self.gpu.textures.set(.swapchain, texture);
    }

    self.drawDemo();
    self.drawUi(draw_data);
    self.drawSolid(draw_data);
}

fn drawDemo(self: *RendererManager) void {
    const texture = self.gpu.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .load = .clear,
        .store = .store,
        .clear_color = Colors.Black.toSdl(),
        .texture = texture,
    };

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    const pipeline = self.gpu.pipelines.get(.demo);
    render_pass.bindGraphicsPipeline(pipeline.pipeline);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);
    // std.log.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);

    render_pass.drawPrimitives(3, 1, 0, 0);
}

fn drawUi(self: *RendererManager, draw_data: *Ecs.components.Graphics.DrawData) void {
    const swapchain_texture = self.gpu.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture,
    };

    impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value));

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    self.clay_manager.renderCommands(draw_data.clay_render_cmds);

    const pipeline = self.gpu.pipelines.get(.ui);
    render_pass.bindGraphicsPipeline(pipeline.pipeline);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp);
    const time_bytes = std.mem.toBytes(self.uniforms.time);

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);
    self.gpu.command_buffer.pushFragmentUniformData(0, &time_bytes);
    render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.gpu.buffers.get(.ui_vertex), .offset = 0 }});
    render_pass.bindIndexBuffer(.{ .buffer = self.gpu.buffers.get(.ui_index), .offset = 0 }, .indices_16bit);
    render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.gpu.textures.get(.atlas), .sampler = self.gpu.samplers.get(.nearest) }});

    render_pass.drawIndexedPrimitives(6, 1, 0, 0, 0);

    if (!self.is_minimised) {
        // Render ImGui
        impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value), @ptrCast(render_pass.value), null);
    }
}

fn drawSolid(self: *RendererManager, draw_data: *Ecs.components.Graphics.DrawData) void {
    const swapchain_texture = self.gpu.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture,
    };

    impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value));

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    self.clay_manager.renderCommands(draw_data.clay_render_cmds);

    const pipeline = self.gpu.pipelines.get(.solid);
    render_pass.bindGraphicsPipeline(pipeline.pipeline);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);
    const time_bytes = std.mem.toBytes(self.uniforms.time);
    // std.log.debug("size {}, time {}", .{ bytes.len, uniform_buffer.time });
    // std.log.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);
    self.gpu.command_buffer.pushFragmentUniformData(0, &time_bytes);
    render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.gpu.buffers.get(.solid_vertex), .offset = 0 }});
    render_pass.bindIndexBuffer(.{ .buffer = self.gpu.buffers.get(.solid_index), .offset = 0 }, .indices_16bit);
    render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.gpu.textures.get(.atlas), .sampler = self.gpu.samplers.get(.nearest) }});

    render_pass.drawIndexedPrimitives(6, 2, 0, 0, 0);
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
