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
    try device.setSwapchainParameters(window.ptr, .sdr, .vsync);
    try device.setAllowedFramesInFlight(3);

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

// fn uploadTextureToGPU(self: *GPU) !void {
//     std.log.info("[GPU.uploadTextureToGPU]", .{});
//
//
//     self.command_buffer = self.device.acquireCommandBuffer() catch {
//         std.log.err("[GPU.sendSetupDataToGpu] {?s}", .{sdl.errors.get()});
//         return;
//     };
//     defer {
//         self.command_buffer.submit() catch {
//             std.log.err("[GPU.sendSetupDataToGpu] Command Buffer error: {?s}", .{sdl.errors.get()});
//         };
//     }
//
//     {
//         const copy_pass = self.command_buffer.beginCopyPass();
//         defer copy_pass.end();
//
//         {
//             const tbo = self.transfer_buffers.get(.atlas_buffer_data);
//             const pipeline = self.pipelines.get(.solid);
//             {
//                 const vbo = self.buffers.get(.solid_vertex);
//                 copy_pass.uploadToBuffer(.{ .transfer_buffer = tbo, .offset = 0 }, .{
//                     .buffer = vbo,
//                     .offset = 0,
//                     // TODO: Vertex Buffer should have more info
//                     .size = pipeline.vertex_size * 2,
//                 }, false);
//             }
//             {
//                 const ibo = self.buffers.get(.solid_index);
//                 copy_pass.uploadToBuffer(.{ .transfer_buffer = tbo, .offset = pipeline.vertex_size }, .{
//                     .buffer = ibo,
//                     .offset = 0,
//                     // TODO: Vertex Buffer should have more info
//                     .size = pipeline.index_size * 2,
//                 }, false);
//             }
//         }
//         {
//             const tbo = self.transfer_buffers.get(.atlas_texture_data);
//             const texture = self.textures.get(.atlas);
//             const img = self.images.get(.atlas);
//             copy_pass.uploadToTexture(.{ .transfer_buffer = tbo, .offset = 0 }, .{
//                 .texture = texture,
//                 .width = @intCast(img.getWidth()),
//                 .height = @intCast(img.getHeight()),
//                 .depth = 1,
//             }, false);
//         }
//     }
//
//     // { // Debug
//     //     if (self.images.get(.atlas)) |img| {
//     //         const pixels = img.getPixels().?;
//     //         std.log.info("Image: {}x{}, {} bytes", .{ img.getWidth(), img.getHeight(), pixels.len });
//     //
//     //         // Check first few pixels (should NOT be all zeros)
//     //         std.log.info("First pixel (format {}): ({}, {}, {})", .{ img.getFormat().?, pixels[0], pixels[1], pixels[2] });
//     //         std.log.info("Pixel at 100: ({}, {}, {})", .{ pixels[300], pixels[301], pixels[302] });
//     //
//     //         // Calculate expected size
//     //         const expected_rgba_size = img.getWidth() * img.getHeight() * 4;
//     //         std.log.info("Expected buffer size: {}", .{expected_rgba_size});
//     //     }
//     // }
// }
