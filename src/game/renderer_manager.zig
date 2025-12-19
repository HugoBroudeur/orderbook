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
gpu_device: *sdl.SDL_GPUDevice,

swapchain_texture: ?*sdl.SDL_GPUTexture = undefined,
command_buffer: ?*sdl.SDL_GPUCommandBuffer = undefined,

window: Window,

pub const Window = struct {
    backend: *sdl.SDL_Window,
    is_minimised: bool = false,
    show_delay: i32 = 2, // TODO: Avoid flickering of window at startup.
    width: i32,
    height: i32,
};

pub fn init(width: i32, height: i32) !RendererManager {
    Ecs.logger.info("[RendererManager.init]", .{});
    var gpu_device: *sdl.SDL_GPUDevice = undefined;

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_GAMEPAD) == false) {
        std.debug.print("Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_init;
    }

    // Create GPU Device
    const flags_gpu = sdl.SDL_GPU_SHADERFORMAT_SPIRV + sdl.SDL_GPU_SHADERFORMAT_DXIL + sdl.SDL_GPU_SHADERFORMAT_METALLIB;
    if (sdl.SDL_CreateGPUDevice(flags_gpu, true, null)) |device| {
        gpu_device = device;
    } else {
        std.debug.print("Error: SDL_CreateGPUDevice(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_CreateGPUDevice;
    }

    return .{
        .backend = .sdl3,
        .gpu_device = gpu_device,
        .window = .{ .backend = undefined, .width = width, .height = height },
    };
}

pub fn deinit(self: *RendererManager) void {
    _ = sdl.SDL_WaitForGPUIdle(self.gpu_device);
    // img_load.DestroyTexture(@ptrCast(gpu_device), @ptrCast(pTextureId));
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

    sdl.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, self.window.backend);
    sdl.SDL_DestroyGPUDevice(self.gpu_device);
    sdl.SDL_DestroyWindow(self.window.backend);
    sdl.SDL_Quit();
}

pub fn create_window(self: *RendererManager, title: []const u8) !void {
    Ecs.logger.info("[RendererManager.create_window]", .{});
    const window_flags = sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN | sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    const main_scale = sdl.SDL_GetDisplayContentScale(@intCast(sdl.SDL_GetPrimaryDisplay()));
    if (sdl.SDL_CreateWindow(title.ptr, @intFromFloat(@as(f32, @floatFromInt(self.window.width)) * main_scale), @intFromFloat(@as(f32, @floatFromInt(self.window.height)) * main_scale), window_flags)) |pointer| {
        self.window.backend = pointer;
    } else {
        std.debug.print("Error: SDL_CreateWindow(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_CreatWindow;
    }

    // Claim window for GPU Device
    if (!sdl.SDL_ClaimWindowForGPUDevice(self.gpu_device, self.window.backend)) {
        std.debug.print("Error: SDL_ClaimWindowForGPUDevice(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_ClaimWindowForGPUDevice;
    }
    _ = sdl.SDL_SetGPUSwapchainParameters(self.gpu_device, self.window.backend, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, sdl.SDL_GPU_PRESENTMODE_VSYNC);
    //const renderer = sdl.SDL_CreateRenderer(window, null); // TODO for Image load ?

    _ = sdl.SDL_SetWindowPosition(self.window.backend, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);

    // Setup Platform/Renderer backends
    _ = impl_sdl3.ImGui_ImplSDL3_InitForSDLGPU(@ptrCast(self.window.backend));
    var init_info: impl_sdlgpu3.ImGui_ImplSDLGPU3_InitInfo = undefined; //= {};
    init_info.Device = @ptrCast(self.gpu_device);
    init_info.ColorTargetFormat = sdl.SDL_GetGPUSwapchainTextureFormat(self.gpu_device, self.window.backend);
    init_info.MSAASamples = sdl.SDL_GPU_SAMPLECOUNT_1;
    _ = impl_sdlgpu3.ImGui_ImplSDLGPU3_Init(&init_info);
}

pub fn setup(self: *RendererManager, ecs_manager: *EcsManager) void {
    ecs_manager.create_single_component_entity(Ecs.components.EnvironmentInfo, .{
        .world_time = 0,
        .window_width = self.window.width,
        .window_height = self.window.height,
    });
    ecs_manager.flush_cmd_buf();
}

pub fn create_render_pass() Ecs.components.Graphics.RenderPass {
    Ecs.logger.info("[RendererManager.create_render_pass]", .{});
    var target_info: sdl.SDL_GPUColorTargetInfo = std.mem.zeroes(sdl.SDL_GPUColorTargetInfo);
    target_info.load_op = sdl.SDL_GPU_LOADOP_CLEAR;
    target_info.store_op = sdl.SDL_GPU_STOREOP_STORE;
    target_info.mip_level = 0;
    target_info.layer_or_depth_plane = 0;
    target_info.cycle = false;

    return .{ .gpu_pass = undefined, .gpu_target_info = target_info };
}

pub fn begin_pass(self: *RendererManager, render_pass: *Ecs.components.Graphics.RenderPass) void {
    Ecs.logger.info("[RendererManager.begin_pass]", .{});
    self.command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.gpu_device); // Acquire a GPU command buffer

    _ = sdl.SDL_AcquireGPUSwapchainTexture(self.command_buffer, self.window.backend, @ptrCast(&self.swapchain_texture), null, null); // Acquire a swapchain texture

    render_pass.gpu_target_info = std.mem.zeroes(sdl.SDL_GPUColorTargetInfo);
    // render_pass.sdl_pass_action.texture = swapchain_texture_val;
    render_pass.gpu_target_info.clear_color = colorToSdlColor(render_pass.clear_color);
    render_pass.gpu_target_info.load_op = sdl.SDL_GPU_LOADOP_CLEAR;
    render_pass.gpu_target_info.store_op = sdl.SDL_GPU_STOREOP_STORE;
    render_pass.gpu_target_info.mip_level = 0;
    render_pass.gpu_target_info.layer_or_depth_plane = 0;
    render_pass.gpu_target_info.cycle = false;

    // Mandatory start a Imgui frame binding
    impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
    impl_sdl3.ImGui_ImplSDL3_NewFrame();
}

pub fn render_frame(self: *RendererManager, render_pass: *Ecs.components.Graphics.RenderPass, ui_draw_data: *ig.ImDrawData) void {
    Ecs.logger.info("[RendererManager.render_frame]", .{});
    self.window.is_minimised = (ui_draw_data.*.DisplaySize.x <= 0.0) or (ui_draw_data.*.DisplaySize.y <= 0.0);

    if (self.swapchain_texture) |swapchain_texture_val| {
        if (!self.window.is_minimised) {
            // This is mandatory: call ImGui_ImplSDLGPU3_PrepareDrawData() to upload the vertex/index buffer!
            impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(ui_draw_data), @ptrCast(self.command_buffer));

            // Setup and start a render pass
            render_pass.gpu_target_info.texture = swapchain_texture_val;

            if (sdl.SDL_BeginGPURenderPass(self.command_buffer, &render_pass.gpu_target_info, 1, null)) |gpu_pass| {
                render_pass.gpu_pass = gpu_pass;

                // Render ImGui
                impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(ui_draw_data), @ptrCast(self.command_buffer), @ptrCast(render_pass.gpu_pass), null);

                sdl.SDL_EndGPURenderPass(render_pass.gpu_pass);
            }
        }
    }
}

pub fn end_pass(self: *RendererManager) void {
    Ecs.logger.info("[RendererManager.end_pass]", .{});

    // Submit the command buffer
    _ = sdl.SDL_SubmitGPUCommandBuffer(self.command_buffer);

    //
    if (self.window.show_delay >= 0) {
        self.window.show_delay -= 1;
    }
    if (self.window.show_delay == 0) { // Visible main window here at start up
        _ = sdl.SDL_ShowWindow(self.window.backend);
    }
}

fn colorToSdlColor(color: Ecs.components.Graphics.Color) sdl.SDL_FColor {
    return .{ .a = color.a, .b = color.b, .g = color.g, .r = color.r };
}
