// Engine-owned font manager: loads a TTF via SDL_ttf, bakes an ASCII glyph
// atlas into one texture registered on the bindless array, and answers Clay's
// text-measurement callback from the cached glyph metrics.
//
// (Moved here from src/game/ — a font atlas is a GPU/renderer resource, not
// game logic. The old src/game/font_manager.zig is legacy and unused by this
// path.)

const std = @import("std");
const log = std.log.scoped(.font_manager);
const sdl = @import("sdl3");
const clay = @import("zclay");

const Engine = @import("../vulkan/engine.zig");
const AllocatedImage = @import("../vulkan/image.zig").AllocatedImage;

const FontManager = @This();

pub const ATLAS_SIZE: u32 = 512;
pub const FIRST_CP: u32 = 32; // space
pub const LAST_CP: u32 = 126; // ~
const GLYPH_COUNT = LAST_CP - FIRST_CP + 1;

pub const GlyphInfo = struct {
    uv_min: [2]f32 = .{ 0, 0 },
    uv_max: [2]f32 = .{ 0, 0 },
    size: [2]f32 = .{ 0, 0 }, // rendered pixel size at base_size
    /// x = left bearing (minx), y = top above baseline (maxy)
    bearing: [2]f32 = .{ 0, 0 },
    advance: f32 = 0,
};

pub const Font = struct {
    sdl_font: sdl.ttf.Font,
    base_size: f32,
    ascent: f32 = 0,
    atlas_slot: u32 = 0,
    glyphs: [GLYPH_COUNT]GlyphInfo = @splat(.{}),

    pub fn glyph(self: *const Font, codepoint: u32) ?*const GlyphInfo {
        if (codepoint < FIRST_CP or codepoint > LAST_CP) return null;
        return &self.glyphs[codepoint - FIRST_CP];
    }
};

allocator: std.mem.Allocator,
font: Font = undefined,
loaded: bool = false,
atlas_image: ?AllocatedImage = null,
engine: ?*Engine = null,

pub fn init(allocator: std.mem.Allocator) FontManager {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *FontManager) void {
    if (self.atlas_image) |*img| {
        if (self.engine) |engine| img.destroy(engine);
    }
    if (self.loaded) self.font.sdl_font.deinit();
    sdl.ttf.quit();
}

/// Loads the font and bakes its atlas. Must run AFTER the resource manager
/// has seeded the basic textures (so the atlas doesn't steal bindless slot 0,
/// which white must own). Idempotent.
pub fn load(self: *FontManager, engine: *Engine, path: []const u8, size: f32) !void {
    if (self.loaded) return;

    sdl.ttf.init() catch |err| {
        log.err("[FontManager] TTF init failed: {?s}", .{sdl.errors.get()});
        return err;
    };

    const path_nil = try self.allocator.dupeZ(u8, path);
    defer self.allocator.free(path_nil);
    const sdl_font = try sdl.ttf.Font.init(path_nil, size);

    self.font = .{ .sdl_font = sdl_font, .base_size = size };
    self.font.ascent = @floatFromInt(sdl_font.getAscent());
    try self.bakeAtlas(engine);
    self.loaded = true;
    log.info("[FontManager] baked atlas for \"{s}\" @ {d}px -> bindless slot {d}", .{ path, size, self.font.atlas_slot });
}

fn bakeAtlas(self: *FontManager, engine: *Engine) !void {
    const atlas = try self.allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 4);
    defer self.allocator.free(atlas);
    @memset(atlas, 0);

    const white: sdl.ttf.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    var pen_x: u32 = 0;
    var pen_y: u32 = 0;
    var row_h: u32 = 0;

    var cp: u32 = FIRST_CP;
    while (cp <= LAST_CP) : (cp += 1) {
        const m = try self.font.sdl_font.getGlyphMetrics(cp);
        var gi: GlyphInfo = .{
            .bearing = .{ @floatFromInt(m.minx), @floatFromInt(m.maxy) },
            .advance = @floatFromInt(m.advance),
        };

        // Space and other whitespace render to nothing; keep advance only.
        if (self.font.sdl_font.renderGlyphBlended(cp, white)) |glyph_surface_raw| {
            var glyph_surface = glyph_surface_raw;
            defer glyph_surface.deinit();
            const conv = try glyph_surface.convertFormat(.array_rgba_32);
            defer conv.deinit();

            const gw: u32 = @intCast(conv.getWidth());
            const gh: u32 = @intCast(conv.getHeight());
            const pitch = conv.getPitch();
            const pixels = conv.getPixels() orelse return error.NullSurfacePixels;

            if (gw > 0 and gh > 0) {
                if (pen_x + gw >= ATLAS_SIZE) {
                    pen_x = 0;
                    pen_y += row_h + 1;
                    row_h = 0;
                }
                if (pen_y + gh >= ATLAS_SIZE) return error.FontAtlasFull;

                var row: u32 = 0;
                while (row < gh) : (row += 1) {
                    const src = row * pitch;
                    const dst = ((pen_y + row) * ATLAS_SIZE + pen_x) * 4;
                    @memcpy(atlas[dst .. dst + gw * 4], pixels[src .. src + gw * 4]);
                }

                gi.size = .{ @floatFromInt(gw), @floatFromInt(gh) };
                gi.uv_min = .{
                    @as(f32, @floatFromInt(pen_x)) / ATLAS_SIZE,
                    @as(f32, @floatFromInt(pen_y)) / ATLAS_SIZE,
                };
                gi.uv_max = .{
                    @as(f32, @floatFromInt(pen_x + gw)) / ATLAS_SIZE,
                    @as(f32, @floatFromInt(pen_y + gh)) / ATLAS_SIZE,
                };

                pen_x += gw + 1;
                row_h = @max(row_h, gh);
            }
        } else |_| {}

        self.font.glyphs[cp - FIRST_CP] = gi;
    }

    // transfer bits are required: upload() copies from a staging buffer
    // (transfer_dst) and transitions layouts accordingly.
    var image = try AllocatedImage.create(engine, .{ .width = ATLAS_SIZE, .height = ATLAS_SIZE }, .r8g8b8a8_unorm, .{ .sampled_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true }, false, 1);
    try image.upload(engine, atlas);
    self.font.atlas_slot = try engine.descriptor.registerImageView(image.view, engine.samplers.get(.linear).vk_sampler);
    self.atlas_image = image;
    self.engine = engine;
}

/// Clay text-measurement callback. `ctx` is the active FontManager, passed
/// via clay.setMeasureTextFunction(*FontManager, ptr, measureText).
pub fn measureText(text: []const u8, config: *clay.TextElementConfig, ctx: *FontManager) clay.Dimensions {
    if (!ctx.loaded) return .{ .w = 0, .h = @floatFromInt(config.font_size) };
    const scale = @as(f32, @floatFromInt(config.font_size)) / ctx.font.base_size;

    var width: f32 = 0;
    for (text) |c| {
        const g = ctx.font.glyph(c) orelse continue;
        width += g.advance * scale + @as(f32, @floatFromInt(config.letter_spacing));
    }
    return .{ .w = width, .h = @floatFromInt(config.font_size) };
}
