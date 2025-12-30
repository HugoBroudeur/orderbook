const std = @import("std");
const sdl = @import("sdl3");

const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const ig = @import("cimgui");

const UiManager = @import("ui_manager.zig");
const EcsManager = @import("ecs_manager.zig");
const Ecs = @import("ecs/ecs.zig");

const RendererManager = @This();

const Backend = enum { sdl3, sokol };

backend: Backend,
allocator: std.mem.Allocator,

init_flags: sdl.InitFlags,
device: sdl.gpu.Device = undefined,
window: sdl.video.Window = undefined,

pipelines: std.ArrayList(sdl.gpu.GraphicsPipeline),
shaders: std.ArrayList(sdl.gpu.Shader),

swapchain_texture: ?sdl.gpu.Texture = undefined,
command_buffer: sdl.gpu.CommandBuffer = undefined,

is_minimised: bool = false,

// const vert_shader_code = @embedFile("shaders/triangle.vert.spv");
// const frag_shader_code = @embedFile("shaders/triangle.frag.spv");
// const vert_shader_code = "test";
// const frag_shader_code = "test";
// const vert_shader_name = "textured_quad.vert";
// const frag_shader_name = "textured_quad.frag";
const vert_shader_name = "triangle.vert";
const frag_shader_name = "triangle.frag";
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
        .pipelines = try .initCapacity(allocator, 1),
        .shaders = try .initCapacity(allocator, 1),
    };
}

pub fn deinit(self: *RendererManager) void {
    self.device.waitForIdle() catch unreachable;
    // img_load.DestroyTexture(@ptrCast(gpu_device), @ptrCast(pTextureId));
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

    for (self.pipelines.items) |pipeline| {
        self.device.releaseGraphicsPipeline(pipeline);
    }
    self.pipelines.deinit(self.allocator);

    for (self.shaders.items) |shader| {
        self.device.releaseShader(shader);
    }
    self.shaders.deinit(self.allocator);

    self.device.releaseWindow(self.window);
    self.device.deinit();

    sdl.quit(self.init_flags);
}

pub fn setup(self: *RendererManager, ecs_manager: *EcsManager, title: []const u8, width: i32, height: i32) !void {
    const t = try self.allocator.dupeZ(u8, title);
    defer self.allocator.free(t);

    try self.createDevice();
    try self.createWindow(t, width, height);
    try self.claimWindow();
    self.initImgui();

    const aspect_ratio = try self.window.getAspectRatio();
    std.log.debug("[RendererManager.setup] Aspect Ratio: {}", .{aspect_ratio});

    ecs_manager.create_single_component_entity(Ecs.components.EnvironmentInfo, .{
        .world_time = 0,
        .window_width = @intFromFloat(aspect_ratio.@"0"),
        .window_height = @intFromFloat(aspect_ratio.@"1"),
    });
    ecs_manager.flush_cmd_buf();

    // try self.createPipeline(.triangle_list);
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
    // Claim window for GPU Device
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

fn createPipeline(self: *RendererManager, primitive_type: sdl.gpu.PrimitiveType) !void {
    std.log.info("[RendererManager.createPipeline] Vert Shader: {s} | Frag Shader: {s} | Primitive: {}", .{ vert_shader_name, frag_shader_name, primitive_type });
    const vertex_shader = try self.createShader(vert_shader_bin, .vertex);
    const frag_shader = try self.createShader(frag_shader_bin, .fragment);

    const pipeline_create_info: sdl.gpu.GraphicsPipelineCreateInfo = .{
        .vertex_shader = vertex_shader,
        .fragment_shader = frag_shader,
        .primitive_type = primitive_type,
    };

    try self.pipelines.append(self.allocator, try self.device.createGraphicsPipeline(pipeline_create_info));
}

pub fn createShader(self: *RendererManager, shader_byte_code: []const u8, stage: sdl.gpu.ShaderStage) !sdl.gpu.Shader {
    const shader_create_info: sdl.gpu.ShaderCreateInfo = .{
        .code = shader_byte_code,
        .entry_point = "main",
        .format = .{ .spirv = true },
        .stage = stage,
    };

    const shader = try self.device.createShader(shader_create_info);
    try self.shaders.append(self.allocator, shader);

    return shader;
}

pub fn createColorTargetInfo() sdl.gpu.ColorTargetInfo {
    Ecs.logger.info("[RendererManager.createColorTargetInfo]", .{});

    var target_info: sdl.gpu.ColorTargetInfo = .{ .texture = .{ .value = null } };
    target_info.load = .clear;
    target_info.store = .store;
    target_info.mip_level = 0;
    target_info.layer_or_depth_plane = 0;
    target_info.cycle = false;

    return target_info;
}

pub fn begin_pass(self: *RendererManager, render_pass: *Ecs.components.Graphics.RenderPass) void {
    Ecs.logger.info("[RendererManager.begin_pass]", .{});

    self.swapchain_texture = null;
    render_pass.gpu_target_info = createColorTargetInfo();
    render_pass.gpu_target_info.clear_color = colorToSdlColor(render_pass.clear_color);

    // self.command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.gpu_device.ptr); // Acquire a GPU command buffer
    self.command_buffer = self.device.acquireCommandBuffer() catch {
        std.log.err("[RendererManager.begin_pass] {?s}", .{sdl.errors.get()});
        return;
    };

    const swapchain_texture = self.command_buffer.waitAndAcquireSwapchainTexture(self.window) catch {
        std.log.err("[RendererManager.begin_pass] {?s}", .{sdl.errors.get()});
        return;
    };

    if (swapchain_texture.@"0") |texture| {
        self.swapchain_texture = texture;

        // Setup and start a render pass
        render_pass.gpu_target_info.texture = texture;
        render_pass.gpu_pass = self.command_buffer.beginRenderPass(&.{render_pass.gpu_target_info}, null);
    }

    // Mandatory start a Imgui frame binding
    impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
    impl_sdl3.ImGui_ImplSDL3_NewFrame();
}

pub fn render_frame(self: *RendererManager, render_pass: *Ecs.components.Graphics.RenderPass, ui_draw_data: *ig.ImDrawData) void {
    Ecs.logger.info("[RendererManager.render_frame]", .{});
    self.is_minimised = (ui_draw_data.*.DisplaySize.x <= 0.0) or (ui_draw_data.*.DisplaySize.y <= 0.0);

    if (render_pass.gpu_pass) |gpu_pass| {
        if (!self.is_minimised) {
            // This is mandatory: call ImGui_ImplSDLGPU3_PrepareDrawData() to upload the vertex/index buffer!
            Ecs.logger.info("[RendererManager.render_frame] Prepare Draw", .{});
            impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(ui_draw_data), @ptrCast(self.command_buffer.value));

            // Render ImGui
            Ecs.logger.info("[RendererManager.render_frame] Render Draw", .{});
            impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(ui_draw_data), @ptrCast(self.command_buffer.value), @ptrCast(gpu_pass.value), null);
        }

        Ecs.logger.info("[RendererManager.render_frame] End GPU Pass", .{});
        gpu_pass.end();
    }
}

pub fn endFrame(self: *RendererManager) void {
    Ecs.logger.info("[RendererManager.endFrame]", .{});

    // Submit the command buffer
    self.command_buffer.submit() catch {
        std.log.err("[RendererManager.endFrame] Command Buffer error: {?s}", .{sdl.errors.get()});
    };

    // //
    // if (self.gpu_device.window.show_delay >= 0) {
    //     self.gpu_device.window.show_delay -= 1;
    // }
    // if (self.gpu_device.window.show_delay == 0) { // Visible main window here at start up
    //     _ = sdl.SDL_ShowWindow(self.gpu_device.window.window);
    // }
}

fn colorToSdlColor(color: Ecs.components.Graphics.Color) sdl.pixels.FColor {
    return .{ .a = color.a, .b = color.b, .g = color.g, .r = color.r };
}

fn log_sdl(userdata: ?*anyopaque, category: c_int, priority: sdl.SDL_LogPriority, message: [*c]const u8) callconv(.c) void {
    _ = userdata;
    const category_str: []const u8 = switch (category) {
        0 => "Application",
        1 => "Errors",
        2 => "Assert",
        3 => "System",
        4 => "Audio",
        5 => "Video",
        6 => "Render",
        7 => "Input",
        8 => "Testing",
        9 => "Gpu",
        else => "Unknown",
    };
    const priority_str: [:0]const u8 = switch (priority) {
        0 => "Invalid",
        1 => "Trace",
        2 => "Verbose",
        3 => "Debug",
        4 => "Info",
        5 => "Warn",
        6 => "Error",
        7 => "Critical",
        8 => "Count",
        else => "Unknown",
    };
    std.log.debug("[SDL] {s} [{s}]: {s}", .{ category_str, priority_str, message });
    // std.log.debug("[SDL] {} [{}]: {s}", .{ category, priority, message });
}
