const std = @import("std");
const sdl = @import("sdl3");

const Texture = @import("texture.zig");
const Window = @import("../app/window.zig");

const GPU = @This();

device: sdl.gpu.Device,
window: *Window,

command_buffer: sdl.gpu.CommandBuffer = undefined,
text_engine: sdl.ttf.GpuTextEngine,

pub fn init(window: *Window) !GPU {
    var device = try sdl.gpu.Device.init(.{ .spirv = true, .dxil = true, .metal_lib = true }, true, null);

    try device.claimWindow(window.ptr);
    try device.setSwapchainParameters(window.ptr, .sdr, .vsync);

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

pub fn mapTransferBuffer(
    self: *GPU,
    transfer_buffer: sdl.gpu.TransferBuffer,
    cycle: bool,
) ![*]u8 {
    self.has_data_mapped = true;
    return self.device.mapTransferBuffer(transfer_buffer, cycle);
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

fn createPipelines(self: *GPU) !void {
    // Setup all resources
    const format = try self.device.getSwapchainTextureFormat(self.window.ptr);
    {
        const pipeline = try self.pipeline_manager.loadDemo(format);
        self.pipelines.set(.demo, pipeline);
    }
    {
        const pipeline = try self.pipeline_manager.loadUi(format);
        self.pipelines.set(.ui, pipeline);
    }
    {
        const pipeline = try self.pipeline_manager.loadSolid(format);
        self.pipelines.set(.solid, pipeline);
    }
}

// fn uploadTextureToGPU(self: *GPU) !void {
//     std.log.info("[GPU.uploadTextureToGPU]", .{});
//
//     {
//         // Set up Buffer Data
//
//         const tbo = self.transfer_buffers.get(.atlas_buffer_data);
//         const gpu_tb_ptr = try self.device.mapTransferBuffer(tbo, false);
//         defer self.device.unmapTransferBuffer(tbo);
//
//         const vertices = [_]PipelineManager.PositionTextureVertex{
//             .{ .pos = zm.f32x4(-1, 1, -0.3, 1), .uv = .{ .u = 0, .v = 0 } },
//             .{ .pos = zm.f32x4(1, 1, -0.3, 1), .uv = .{ .u = 1, .v = 0 } },
//             .{ .pos = zm.f32x4(1, -1, -0.3, 1), .uv = .{ .u = 1, .v = 1 } },
//             .{ .pos = zm.f32x4(-1, -1, -0.3, 1), .uv = .{ .u = 0, .v = 1 } },
//
//             .{ .pos = zm.f32x4(-1, 1, -1, 1), .uv = .{ .u = 0, .v = 0 } },
//             .{ .pos = zm.f32x4(1, 1, -1, 1), .uv = .{ .u = 1, .v = 0 } },
//             .{ .pos = zm.f32x4(1, -1, -1, 1), .uv = .{ .u = 1, .v = 1 } },
//             .{ .pos = zm.f32x4(-1, -1, -1, 1), .uv = .{ .u = 0, .v = 1 } },
//         };
//         const indices = [_]u16{
//             0, 1, 2, 0, 2, 3,
//             // 0, 1, 2, 0, 2, 3,
//         };
//
//         const vertex_bytes = @sizeOf(@TypeOf(vertices));
//         const index_bytes = @sizeOf(@TypeOf(indices));
//
//         std.mem.copyForwards(u8, gpu_tb_ptr[0..vertex_bytes], std.mem.asBytes(&vertices));
//         std.mem.copyForwards(u8, gpu_tb_ptr[vertex_bytes..(vertex_bytes + index_bytes)], std.mem.asBytes(&indices));
//     }
//
//     // Set up Texture Data with detailed logging
//     // if (self.transfer_buffers.get(.atlas_texture_data)) |tbo| {
//     //     std.log.info("Got transfer buffer", .{});
//     //
//     //     const gpu_tb_ptr = try self.device.mapTransferBuffer(tbo, false);
//     //     defer self.device.unmapTransferBuffer(tbo);
//     //     std.log.info("Mapped transfer buffer", .{});
//     //
//     //     if (self.images.get(.atlas)) |img| {
//     //         const pixels = img.getPixels().?;
//     //         const width = img.getWidth();
//     //         const height = img.getHeight();
//     //
//     //         std.log.info("Image info: {}x{}, {} bytes", .{ width, height, pixels.len });
//     //         std.log.info("Pixel format: {}", .{img.getFormat().?});
//     //         std.log.info("Expected: {} bytes", .{width * height * 4});
//     //         std.log.info("First 16 bytes: [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}]", .{ pixels[0], pixels[1], pixels[2], pixels[3], pixels[4], pixels[5], pixels[6], pixels[7], pixels[8], pixels[9], pixels[10], pixels[11], pixels[12], pixels[13], pixels[14], pixels[15] });
//     //
//     //         @memcpy(gpu_tb_ptr[0..pixels.len], pixels);
//     //
//     //         std.log.info("After memcpy, first 16 bytes in GPU buffer: [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}] [{}, {}, {}, {}]", .{ gpu_tb_ptr[0], gpu_tb_ptr[1], gpu_tb_ptr[2], gpu_tb_ptr[3], gpu_tb_ptr[4], gpu_tb_ptr[5], gpu_tb_ptr[6], gpu_tb_ptr[7], gpu_tb_ptr[8], gpu_tb_ptr[9], gpu_tb_ptr[10], gpu_tb_ptr[11], gpu_tb_ptr[12], gpu_tb_ptr[13], gpu_tb_ptr[14], gpu_tb_ptr[15] });
//     //     } else {
//     //         std.log.err("Image .atlas not found!", .{});
//     //     }
//     // } else {
//     //     std.log.err("Transfer buffer .atlas_texture_data not found!", .{});
//     // }
//
//     {
//         // Set up Texture Data
//
//         const tbo = self.transfer_buffers.get(.atlas_texture_data);
//         const gpu_tb_ptr = try self.device.mapTransferBuffer(tbo, false);
//         defer self.device.unmapTransferBuffer(tbo);
//
//         const img = self.images.get(.atlas);
//         @memcpy(gpu_tb_ptr[0..img.getPixels().?.len], img.getPixels().?);
//     }
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
