const std = @import("std");
const sdl = @cImport({
    // @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});
const clay = @import("zclay");

const FontManager = @This();

pub const fonts: [2][]const u8 = .{
    "assets/fonts/SNPro/SNPro-Regular.ttf",
    "assets/fonts/ferrum.otf",
};

var loaded_fonts: std.AutoArrayHashMap(FontKey, Font) = undefined;

allocator: std.mem.Allocator,
is_init: bool,

var current_id: u16 = 0;

pub const Font = struct {
    ttf_path: []const u8,
    sdl_font: *sdl.TTF_Font,
    base_size: f32,

    pub fn init(path: []const u8, sdl_font: *sdl.TTF_Font, font_size: f32) Font {
        return .{ .ttf_path = path, .sdl_font = sdl_font, .base_size = font_size };
    }
};

pub const FontKey = struct {
    id: u16,
};

pub fn init(allocator: std.mem.Allocator) FontManager {
    loaded_fonts = .init(allocator);
    return .{
        .allocator = allocator,
        .is_init = false,
    };
}

pub fn deinit(self: *FontManager) void {
    _ = self;
    var it = loaded_fonts.iterator();
    while (it.next()) |font| {
        sdl.TTF_CloseFont(font.value_ptr.sdl_font);
    }
    loaded_fonts.deinit();

    sdl.TTF_Quit();
}

pub fn setup(self: *FontManager) !void {
    if (sdl.TTF_Init() == false) {
        std.log.err("[FontManager] Can't start SDL TTF. Reason: {s}", .{sdl.SDL_GetError()});
        return error.FontManagerInit;
    }

    self.is_init = true;
}

pub fn addFont(path: []const u8, size: f32) FontKey {
    const key = openFont(path, size) catch {
        std.log.err("Can't load font {s}. Reason {s}", .{ path, sdl.SDL_GetError() });
        return .{ .id = current_id };
    };

    std.log.info("[FontManager.addFont] Loaded Font ID [{d}], path \"{s}\", size {d}", .{ key.id, path, size });

    return key;
}

pub fn getFont(id: u16) ?Font {
    return loaded_fonts.get(.{ .id = id });
}

pub fn measureText(text: []const u8, config: *clay.TextElementConfig, _: void) clay.Dimensions {
    var width: i32 = 0;
    var height: i32 = 0;

    const font = getFont(config.font_id).?;

    _ = sdl.TTF_SetFontSize(@alignCast(font.sdl_font), @floatFromInt(config.font_size));
    if (!sdl.TTF_GetStringSize(font.sdl_font, text.ptr, text.len, &width, &height)) {
        std.log.err("[FontManager] Failed measuring text: {s}", .{sdl.SDL_GetError()});
        // sdl.SDL_LogError(sdl.SDL_LOG_CATEGORY_ERROR, "[FontManager] Failed measuring text: %s", .{sdl.SDL_GetError()});
    }

    return .{ .w = @floatFromInt(width), .h = @floatFromInt(height) };
}

fn openFont(path: []const u8, size: f32) !FontKey {
    const font = sdl.TTF_OpenFont(path.ptr, size);
    if (font) |f| {
        const key: FontKey = .{ .id = current_id };

        try loaded_fonts.put(key, Font.init(path, f, size));
        current_id += 1;

        return key;
    }

    return error.OpenFont;
}
