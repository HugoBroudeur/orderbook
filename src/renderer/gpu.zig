const std = @import("std");
const sdl = @import("sdl3");

const Texture = @import("texture.zig");
const Window = @import("../core/window.zig");

const GPU = @This();

device: sdl.gpu.Device,
window: *Window,

command_buffer: sdl.gpu.CommandBuffer = undefined,
text_engine: sdl.ttf.GpuTextEngine,

pub fn init(window: *Window) !GPU {
    var device = try sdl.gpu.Device.init(.{ .spirv = true, .dxil = true, .metal_lib = true }, true, null);
    try device.claimWindow(window.ptr);

    const frame_in_flight = 2;
    try setSwapchainParameters(&device, window, frame_in_flight);

    const text_engine = try sdl.ttf.GpuTextEngine.init(device);

    return .{
        .device = device,
        .window = window,
        .text_engine = text_engine,
    };
}

pub fn deinit(self: *GPU) void {
    self.device.waitForIdle() catch unreachable;

    self.text_engine.deinit();

    self.device.releaseWindow(self.window.ptr);
    self.device.deinit();
}

pub fn getSwapchainTextureFormat(self: *GPU) !Texture.TextureFormat {
    return .{ .ptr = try self.device.getSwapchainTextureFormat(self.window.ptr) };
}

pub fn acquireSwapchainTexture(self: *GPU) !?Texture {
    const swapchain_image = try self.command_buffer.acquireSwapchainTexture(self.window.ptr);
    const _ptr = swapchain_image.@"0";
    const width = swapchain_image.@"1";
    const heigth = swapchain_image.@"2";

    if (_ptr) |ptr| {
        return Texture.createFromPtr(self, ptr, width, heigth);
    }

    return null;
}

fn setSwapchainParameters(device: *sdl.gpu.Device, window: *Window, frame_in_flight: u32) !void {
    var present_mode: sdl.gpu.PresentMode = .vsync;
    if (device.windowSupportsPresentMode(window.ptr, .mailbox)) {
        present_mode = .mailbox;
    }
    if (device.windowSupportsPresentMode(window.ptr, .immediate)) {
        present_mode = .immediate;
    }
    // if (device.windowSupportsPresentMode(window.ptr, .vsync)) {
    //     present_mode = .vsync;
    // }

    var composition: sdl.gpu.SwapchainComposition = .sdr;
    if (device.windowSupportsSwapchainComposition(window.ptr, .sdr_linear)) {
        composition = .sdr_linear;
    }
    if (device.windowSupportsSwapchainComposition(window.ptr, .hdr10_st2084)) {
        composition = .hdr10_st2084;
    }
    if (device.windowSupportsSwapchainComposition(window.ptr, .hdr_extended_linear)) {
        composition = .hdr_extended_linear;
    }

    std.log.info(
        \\==================== GPU info ====================
        \\  Drivers count                         : {}
        \\  Support VSync                         : {}
        \\  Support Mailbox                       : {}
        \\  Support Immediate                     : {}
        \\  Support Swapchain sdr                 : {}
        \\  Support Swapchain sdr_linear          : {}
        \\  Support Swapchain hdr10_st2084        : {}
        \\  Support Swapchain hdr_extended_linear : {}
        \\  Chosen mode                           : {s}
        \\  Chosen composition                    : {s}
    ,
        .{
            sdl.gpu.getNumDrivers(),
            device.windowSupportsPresentMode(window.ptr, .vsync),
            device.windowSupportsPresentMode(window.ptr, .mailbox),
            device.windowSupportsPresentMode(window.ptr, .immediate),
            device.windowSupportsSwapchainComposition(window.ptr, .sdr),
            device.windowSupportsSwapchainComposition(window.ptr, .sdr_linear),
            device.windowSupportsSwapchainComposition(window.ptr, .hdr10_st2084),
            device.windowSupportsSwapchainComposition(window.ptr, .hdr_extended_linear),
            @tagName(present_mode),
            @tagName(composition),
        },
    );

    try device.setSwapchainParameters(window.ptr, composition, present_mode);
    try device.setAllowedFramesInFlight(frame_in_flight);
}
