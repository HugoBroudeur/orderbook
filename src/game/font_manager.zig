const std = @import("std");
const sdl = @import("sdl3");
const clay = @import("zclay");

const FontManager = @This();

pub const fonts: [2][]const u8 = .{
    "assets/fonts/SNPro/SNPro-Regular.ttf",
    "assets/fonts/ferrum.otf",
};

pub const MainFont = "assets/fonts/SNPro/SNPro-Regular.ttf";

loaded_fonts: std.AutoArrayHashMap(FontKey, Font),

allocator: std.mem.Allocator,
is_init: bool,

var current_id: u16 = 0;

pub const Font = struct {
    ttf_path: []const u8,
    sdl_font: sdl.ttf.Font,
    base_size: f32,

    pub fn init(path: []const u8, sdl_font: sdl.ttf.Font, font_size: f32) Font {
        return .{ .ttf_path = path, .sdl_font = sdl_font, .base_size = font_size };
    }
};

pub const FontKey = struct {
    id: u16,
};

pub fn init(allocator: std.mem.Allocator) FontManager {
    return .{
        .allocator = allocator,
        .loaded_fonts = .init(allocator),
        .is_init = false,
    };
}

pub fn deinit(self: *FontManager) void {
    var it = self.loaded_fonts.iterator();
    while (it.next()) |font| {
        font.value_ptr.sdl_font.deinit();
    }
    self.loaded_fonts.deinit();

    sdl.ttf.quit();
}

pub fn setup(self: *FontManager) !void {
    sdl.ttf.init() catch |err| {
        std.log.err("[FontManager] Can't start SDL TTF. Reason: {?s}", .{sdl.errors.get()});
        return err;
    };

    self.is_init = true;
}

pub fn addFont(self: *FontManager, path: []const u8, size: f32) !FontKey {
    const key = try self.openFont(path, size);

    std.log.info("[FontManager.addFont] Loaded Font ID [{d}], path \"{s}\", size {d}", .{ key.id, path, size });

    return key;
}

pub fn getFont(self: *FontManager, key: FontKey) ?Font {
    return self.loaded_fonts.get(.{ .id = key.id });
}

pub fn measureText(text: []const u8, config: *clay.TextElementConfig, _: void) clay.Dimensions {
    _ = text;
    _ = config;
    // var width: i32 = 0;
    // var height: i32 = 0;
    const width: i32 = 0;
    const height: i32 = 0;

    // const font = getFont(.{ .id = config.font_id }).?;

    // font.sdl_font.setSize(@floatFromInt(config.font_size)) catch {
    //     std.log.err("[FontManager.measureText] Can't set font size", .{});
    // };

    // width, height = font.sdl_font.getStringSize(text) catch .{ 0, 0 };

    return .{ .w = @floatFromInt(width), .h = @floatFromInt(height) };
}

fn openFont(self: *FontManager, path: []const u8, size: f32) !FontKey {
    const path_nil = try self.allocator.dupeZ(u8, path);
    defer self.allocator.free(path_nil);
    const sdl_font = try sdl.ttf.Font.init(path_nil, size);

    const key: FontKey = .{ .id = current_id };

    try self.loaded_fonts.put(key, Font.init(path, sdl_font, size));
    current_id += 1;

    return key;
}
