const std = @import("std");
const sdl = @import("sdl3");

const RendererManager = @This();

const Backend = enum { sdl3, sokol };

backend: Backend,
window: *sdl.SDL_Window,
gpu_device: *sdl.SDL_GPUDevice,

pub fn init() !RendererManager {
    var gpu_device: *sdl.SDL_GPUDevice = undefined;
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
        .window = undefined,
    };
}

pub fn deinit(self: *RendererManager) void {
    _ = self;
}

pub fn create_window(self: *RendererManager, width: f32, height: f32) void {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_GAMEPAD) == false) {
        std.debug.print("Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_init;
    }

    const window_flags = sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN | sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    const main_scale = sdl.SDL_GetDisplayContentScale(@intCast(sdl.SDL_GetPrimaryDisplay()));
    if (sdl.SDL_CreateWindow("SDL3GPU example", @intFromFloat(width * main_scale), @intFromFloat(height * main_scale), window_flags)) |pointer| {
        self.window = pointer;
    } else {
        std.debug.print("Error: SDL_CreateWindow(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_CreatWindow;
    }

    // Claim window for GPU Device
    if (!sdl.SDL_ClaimWindowForGPUDevice(self.gpu_device, self.window)) {
        std.debug.print("Error: SDL_ClaimWindowForGPUDevice(): {s}\n", .{sdl.SDL_GetError()});
        return error.SDL_ClaimWindowForGPUDevice;
    }
    _ = sdl.SDL_SetGPUSwapchainParameters(self.gpu_device, self.window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, sdl.SDL_GPU_PRESENTMODE_VSYNC);
    //const renderer = sdl.SDL_CreateRenderer(window, null); // TODO for Image load ?

    _ = sdl.SDL_SetWindowPosition(self.window, sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED);
}
