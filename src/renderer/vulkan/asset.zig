// This is an SDL implementation
const std = @import("std");
const sdl = @import("sdl3");

const Asset = @This();

pub const ImageFormat = enum { jpg };

pub fn createSurface(image_path: [:0]const u8, format: ImageFormat) !sdl.surface.Surface {
    std.log.info("[Asset.createSurface]", .{});

    const stream = try sdl.io_stream.Stream.initFromFile(image_path, .read_text);

    const surface = switch (format) {
        .jpg => try sdl.image.loadJpgIo(stream),
    };
    defer surface.deinit();

    const surface_formated = try surface.convertFormat(.array_rgba_32);

    std.log.info("Image info: {}x{}, {} bytes", .{ surface_formated.getWidth(), surface_formated.getHeight(), surface_formated.getPixels().?.len });
    std.log.info("Pixel format: {}", .{surface_formated.getFormat().?});
    std.log.info("Expected: {} bytes", .{surface_formated.getWidth() * surface_formated.getHeight() * 4});

    return surface_formated;
}
