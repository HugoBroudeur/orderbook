const std = @import("std");
const sdl = @import("sdl3");

const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ig = @import("cimgui");

const UiManager = @import("ui_manager.zig");
const EcsManager = @import("ecs_manager.zig");
const PipelineManager = @import("pipeline_manager.zig");
const Ecs = @import("ecs/ecs.zig");
const Colors = @import("colors.zig");

const RendererManager = @This();

const Backend = enum { sdl3, sokol };
pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };

backend: Backend,
allocator: std.mem.Allocator,

init_flags: sdl.InitFlags,
device: sdl.gpu.Device = undefined,
window: sdl.video.Window = undefined,
window_size: struct {
    width: u32 = 0,
    height: u32 = 0,
} = .{},

// pipelines: std.ArrayList(sdl.gpu.GraphicsPipeline),
pipelines: std.EnumArray(DrawPassType, ?sdl.gpu.GraphicsPipeline),
textures: std.EnumArray(DrawPassType, ?sdl.gpu.Texture),

swapchain_texture: ?sdl.gpu.Texture = undefined,
command_buffer: sdl.gpu.CommandBuffer = undefined,

is_minimised: bool = false,

// From "src/shaders/"
// const vert_shader_name = "triangle.vert";
const frag_shader_name = "triangle";
const vert_shader_name = "triangle";
// const frag_shader_name = "solid_color.frag";
const vert_shader_bin = @embedFile(vert_shader_name ++ ".spv");
const frag_shader_bin = @embedFile(frag_shader_name ++ ".spv");

pub const fonts: [2][]const u8 = .{
    "assets/fonts/SNPro/SNPro-Regular.ttf",
    "assets/fonts/ferrum.otf",
};
pub const font_size: f32 = 18;

var font: ?*sdl.ttf.Font = undefined;

var tiny_ttf = "assets/fonts/SNPro/SNPro-Regular.ttf";

pub const Window = struct {
    // ptr: *sdl.video.Window,
    // window: sdl.video.Window,
    show_delay: i32 = 2, // TODO: Avoid flickering of window at startup.
    width: i32,
    height: i32,
};

pub fn init(allocator: std.mem.Allocator) !RendererManager {
    Ecs.logger.info("[RendererManager.init]", .{});

    const init_flags: sdl.InitFlags = .{ .video = true, .gamepad = true, .audio = true };
    sdl.init(init_flags) catch |err| {
        std.log.err("Error: {?s}", .{sdl.errors.get()});
        return err;
    };

    sdl.log.setAllPriorities(.debug);

    return .{
        .allocator = allocator,
        .backend = .sdl3,
        .init_flags = init_flags,
        .pipelines = .initFill(null),
        .textures = .initFill(null),
    };
}

pub fn deinit(self: *RendererManager) void {
    self.device.waitForIdle() catch unreachable;
    // img_load.DestroyTexture(@ptrCast(gpu_device), @ptrCast(pTextureId));
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

    for (self.pipelines.values) |pipeline| {
        if (pipeline) |p| {
            self.device.releaseGraphicsPipeline(p);
        }
    }

    self.device.releaseWindow(self.window);
    self.device.deinit();

    sdl.quit(self.init_flags);
}

pub fn setup(self: *RendererManager, ecs_manager: *EcsManager, pipeline_manager: *PipelineManager, title: []const u8, width: i32, height: i32) !void {
    const t = try self.allocator.dupeZ(u8, title);
    defer self.allocator.free(t);

    try self.createDevice();
    try self.createWindow(t, width, height);
    try self.claimWindow();
    self.initImgui();

    // const aspect_ratio = try self.window.getAspectRatio();
    // std.log.debug("[RendererManager.setup] Aspect Ratio: {}", .{aspect_ratio});
    const size = try self.window.getSize();
    std.log.debug("[RendererManager.setup] Size: {}", .{size});

    ecs_manager.create_single_component_entity(Ecs.components.EnvironmentInfo, .{
        .world_time = 0,
        .window_width = @intCast(size.@"0"),
        .window_height = @intCast(size.@"1"),
    });
    ecs_manager.flush_cmd_buf();

    const format = try self.device.getSwapchainTextureFormat(self.window);

    // Setup pipelines
    self.pipelines.set(.demo, try pipeline_manager.loadDemo(format));
}

fn createDevice(self: *RendererManager) !void {
    self.device = sdl.gpu.Device.init(.{ .spirv = true, .dxil = true, .metal_lib = true }, true, null) catch |err| {
        std.log.err("[RendererManager] SDL_CreateGPUDevice(): {?s}", .{sdl.errors.get()});
        return err;
    };
}

fn createWindow(self: *RendererManager, title: [:0]const u8, width: i32, height: i32) !void {
    const window_flags: sdl.video.Window.Flags = .{ .resizable = true, .hidden = false, .high_pixel_density = true };
    const main_scale = try sdl.video.Display.getContentScale(try sdl.video.Display.getPrimaryDisplay());

    self.window = sdl.video.Window.init(title, @intFromFloat(@as(f32, @floatFromInt(width)) * main_scale), @intFromFloat(@as(f32, @floatFromInt(height)) * main_scale), window_flags) catch |err| {
        std.log.err("Error: SDL_CreateWindow(): {?s}", .{sdl.errors.get()});
        return err;
    };
}

fn claimWindow(self: *RendererManager) !void {
    self.device.claimWindow(self.window) catch |err| {
        std.log.err("Error: SDL_ClaimWindowForGPUDevice(): {?s}", .{sdl.errors.get()});
        return err;
    };

    try self.device.setSwapchainParameters(self.window, .sdr, .vsync);
    try self.window.setPosition(
        .{ .centered = try self.window.getDisplayForWindow() },
        .{ .centered = try self.window.getDisplayForWindow() },
    );
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

fn createColorTargetInfo(texture: sdl.gpu.Texture, clear_color: sdl.pixels.FColor) sdl.gpu.ColorTargetInfo {
    return .{
        .load = .clear,
        .store = .store,
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .cycle = false,
        .texture = texture,
        .clear_color = clear_color,
    };
}

// pub fn startFrame(self: *RendererManager, render_pass: *Ecs.components.Graphics.RenderPass) void {
pub fn startFrame(self: *RendererManager) void {
    Ecs.logger.info("[RendererManager.startFrame]", .{});
    _ = self;

    // Mandatory start a Imgui frame binding
    impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
    impl_sdl3.ImGui_ImplSDL3_NewFrame();
}

pub fn renderFrame(self: *RendererManager, draw_data: *Ecs.components.Graphics.DrawData) void {
    Ecs.logger.info("[RendererManager.renderFrame]", .{});

    self.is_minimised = (draw_data.ui.*.DisplaySize.x <= 0.0) or (draw_data.ui.*.DisplaySize.y <= 0.0);

    self.command_buffer = self.device.acquireCommandBuffer() catch {
        std.log.err("[RendererManager.renderFrame] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.command_buffer.submit() catch {
            std.log.err("[RendererManager.renderFrame] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    const swapchain_image = self.command_buffer.waitAndAcquireSwapchainTexture(self.window) catch {
        std.log.err("[RendererManager.renderFrame] {?s}", .{sdl.errors.get()});
        self.command_buffer.cancel() catch {};
        return;
    };

    // if (swapchain_image.@"1" != self.window.getSize())

    if (swapchain_image.@"0") |texture| {
        self.textures.set(.ui, texture);
        self.textures.set(.demo, texture);

        self.drawDemo();
        self.drawUi(draw_data);
    }
}

fn drawDemo(self: *RendererManager) void {
    if (self.textures.get(.demo)) |texture| {
        const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
            .load = .clear,
            .store = .store,
            .clear_color = Colors.Teal.toSdl(),
            .texture = texture,
        };

        // Setup and start a render pass
        const render_pass = self.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
        defer render_pass.end();

        if (self.pipelines.get(.demo)) |pipeline| {
            render_pass.bindGraphicsPipeline(pipeline);
            // TODO viewport
            // TODO scisor
        }

        render_pass.drawPrimitives(3, 1, 0, 0);
    }
}

fn drawUi(self: *RendererManager, draw_data: *Ecs.components.Graphics.DrawData) void {
    if (self.textures.get(.ui)) |texture| {
        const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
            .store = .store,
            .texture = texture,
        };

        impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data.ui), @ptrCast(self.command_buffer.value));

        // Setup and start a render pass
        const render_pass = self.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
        defer render_pass.end();

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
