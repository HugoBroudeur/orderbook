const std = @import("std");
const log = std.log.scoped(.font);
const sdl = @import("sdl3");

const ResourceManager = @import("manager.zig");
const Resource = @import("resource.zig").Resource;
const ResourceId = @import("resource.zig").ResourceId;
const Texture = @import("texture.zig").Texture;

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

/// Implementation of the Font Resource that is managed by the Resource manager.
///
/// A Font is a TTF loaded at one base size via SDL_ttf, baked into an ASCII
/// glyph atlas. Its GPU side is a regular Texture resource loaded through the
/// manager (ref-counted atlas Image + sampler + bindless slot), so a font
/// participates in the same residency/ref-count rules as every other resource.
pub const Font = struct {
    id: ResourceId,
    name: []const u8,
    source: Source,

    sdl_font: sdl.ttf.Font = undefined,
    base_size: f32 = 0,
    ascent: f32 = 0,
    glyphs: [GLYPH_COUNT]GlyphInfo = @splat(.{}),
    /// Baked RGBA atlas pixels — owned by the Font (not freed after upload)
    /// so the Texture/Image `source` slices stay valid for the resource's
    /// whole lifetime, not just until the synchronous load returns.
    atlas_pixels: []u8 = &.{},
    texture: *Texture = undefined,
    /// Kept to release the Texture ref in unload.
    texture_id: ResourceId = 0,

    pub const Source = union(enum) {
        /// TTF file on disk, baked at `size` px. The path's backing memory
        /// must outlive the Font (comptime literals qualify).
        file: struct { path: []const u8, size: f32 },
    };

    pub fn interface(self: *Font) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: ResourceId, name: []const u8, source: Source) Font {
        return .{
            .id = id,
            .name = name,
            .source = source,
        };
    }

    pub fn getId(self: *const Font) ResourceId {
        return self.id;
    }

    pub fn glyph(self: *const Font, codepoint: u32) ?*const GlyphInfo {
        if (codepoint < FIRST_CP or codepoint > LAST_CP) return null;
        return &self.glyphs[codepoint - FIRST_CP];
    }

    /// Bindless slot of the glyph atlas.
    pub fn atlasSlot(self: *const Font) u32 {
        return self.texture.slot;
    }

    pub fn load(self: *Font, res_manager: *ResourceManager) !void {
        const allocator = res_manager.allocator;

        switch (self.source) {
            .file => |f| {
                // SDL_ttf init/quit are ref-counted, so per-font pairing is safe.
                sdl.ttf.init() catch |err| {
                    log.err("[Font.load] TTF init failed: {?s}", .{sdl.errors.get()});
                    return err;
                };
                errdefer sdl.ttf.quit();

                const path_nil = try allocator.dupeZ(u8, f.path);
                defer allocator.free(path_nil);
                self.sdl_font = try sdl.ttf.Font.init(path_nil, f.size);
                errdefer self.sdl_font.deinit();

                self.base_size = f.size;
                self.ascent = @floatFromInt(self.sdl_font.getAscent());

                self.atlas_pixels = try allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 4);
                errdefer {
                    allocator.free(self.atlas_pixels);
                    self.atlas_pixels = &.{};
                }
                try self.bakeAtlas();

                // GPU side: a plain Texture resource over the baked pixels.
                // Same id as the Font — the pool namespaces ids per type.
                const handle = try res_manager.loadTexture(Texture.init(self.id, self.name, .{
                    .raw_pixels = .{ .pixels = self.atlas_pixels, .size = ATLAS_SIZE },
                }));
                self.texture = handle.get().?;
                self.texture_id = handle._id;

                log.info("[Font.load] baked atlas for \"{s}\" @ {d}px -> bindless slot {d}", .{ f.path, f.size, self.texture.slot });
            },
        }
    }

    pub fn unload(self: *Font, res_manager: *ResourceManager) void {
        res_manager.release(Texture, self.texture_id);
        res_manager.allocator.free(self.atlas_pixels);
        self.sdl_font.deinit();
        sdl.ttf.quit();
    }

    /// Render every ASCII glyph into `atlas_pixels` (simple row packer) and
    /// record its metrics + atlas UVs in `glyphs`.
    fn bakeAtlas(self: *Font) !void {
        @memset(self.atlas_pixels, 0);

        const white: sdl.ttf.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
        var pen_x: u32 = 0;
        var pen_y: u32 = 0;
        var row_h: u32 = 0;

        var cp: u32 = FIRST_CP;
        while (cp <= LAST_CP) : (cp += 1) {
            const m = try self.sdl_font.getGlyphMetrics(cp);
            var gi: GlyphInfo = .{
                .bearing = .{ @floatFromInt(m.minx), @floatFromInt(m.maxy) },
                .advance = @floatFromInt(m.advance),
            };

            // Space and other whitespace render to nothing; keep advance only.
            if (self.sdl_font.renderGlyphBlended(cp, white)) |glyph_surface_raw| {
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
                        @memcpy(self.atlas_pixels[dst .. dst + gw * 4], pixels[src .. src + gw * 4]);
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

            self.glyphs[cp - FIRST_CP] = gi;
        }
    }
};
