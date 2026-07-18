const std = @import("std");

const ResourceManager = @import("manager.zig");
const Resource = @import("resource.zig").Resource;
const ResourceId = @import("resource.zig").ResourceId;
const Gltf = @import("zgltf").Gltf;

const VulkanImage = @import("../engine/vulkan/image.zig");
const AllocatedImage = VulkanImage.AllocatedImage;
const ImageMetadata = VulkanImage.ImageMetadata;
const ImageDataKind = VulkanImage.ImageDataKind;
const Dimension = VulkanImage.Dimension;
const Color = @import("../primitive.zig").Color;

/// Implementation of the Vulkan Image Resource that is managed by the Resource manager.
pub const Image = struct {
    id: ResourceId,
    name: []const u8,
    source: Source,

    allocated_image: AllocatedImage = undefined,
    /// False when load fell back to error_checker (image owned by the engine).
    owns_image: bool = true,

    pub const Source = union(enum) {
        gltf_image: struct { gltf: *Gltf, image_idx: u32 },
        file: []const u8,
        /// glTF texture had no source image -> checker fallback (the
        /// resource manager's basic checker texture, borrowed not owned).
        missing,
        /// NxN solid pixel data generated at load time, not read from any
        /// file — used by AssetManager's basic placeholder textures.
        solid: struct { pixels: []const u8, size: u32 },
    };

    pub fn interface(self: *Image) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: ResourceId, name: []const u8, source: Source) Image {
        return .{
            .id = id,
            .name = name,
            .source = source,
        };
    }

    pub fn getId(self: *const Image) ResourceId {
        return self.id;
    }

    pub fn load(self: *Image, res_manager: *ResourceManager) !void {
        const engine = res_manager.engine;

        const kind: ?ImageDataKind = switch (self.source) {
            .gltf_image => |s| blk: {
                const img = s.gltf.data.images[s.image_idx];
                if (img.uri) |uri| break :blk .{ .path = uri };
                if (img.data) |d| break :blk .{ .pixels = .{ .data = d } };
                break :blk null;
            },
            .file => |path| .{ .path = path },
            .missing => null,
            // `Color.toBytes()` produces literal [R,G,B,A] memory-byte
            // order. That's `array_rgba_32`, not `packed_rgba_8_8_8_8` —
            // "packed" formats are named by bit position in a native-endian
            // integer, so on this little-endian target `packed_rgba_8_8_8_8`
            // actually means memory bytes [A,B,G,R] (`array_rgba_32` is
            // itself documented as an alias for `packed_abgr_8_8_8_8` here,
            // not `packed_rgba_8_8_8_8`). Labeling raw RGBA bytes with the
            // packed tag silently shuffles channels on conversion.
            .solid => |s| .{ .pixels = .{ .data = s.pixels, .format = .array_rgba_32 } },
        };

        if (kind) |k| {
            // .pixels + a null dimension means "sniff/decode these bytes as
            // an image file format" (SDL_image) — wrong for raw solid-color
            // framebuffer bytes, so .solid must pass its own size through.
            const dimension: ?Dimension = switch (self.source) {
                .solid => |s| .{ .width = s.size, .height = s.size, .depth = 1 },
                else => null,
            };
            // Mipmapping a flat/pattern placeholder is actively wrong, not
            // just unnecessary: downsampling a 2x2 checker blends its two
            // colors into a flat grey-ish mip 1, so any surface that samples
            // a non-zero LOD (anything not screen-filling) shows that
            // blended color instead of the checker pattern — reads as "the
            // texture went missing / rendered the wrong color". White/black/
            // grey are single-pixel and unaffected either way (mip count is
            // 1 regardless), but keep them off the mipmap path too, for the
            // same reason: nothing here is real photographic content.
            const is_mipmapped = switch (self.source) {
                .solid => false,
                else => true,
            };
            const meta = ImageMetadata.init(k, dimension);
            self.allocated_image = try meta.allocateImage(engine, .{ .sampled_bit = true }, is_mipmapped, 1);
            try meta.upload(engine, self.allocated_image);
        } else {
            // Borrow the resource manager's own checker texture rather than
            // a separate engine-owned copy — one basic-texture system, not
            // two. Guaranteed loaded: AssetManager.initBasicTextures runs
            // before anything else can reach this fallback.
            self.allocated_image = res_manager.getResource(Image, res_manager.common_resources.image.checker).?.allocated_image;
            self.owns_image = false;
        }
    }

    pub fn unload(self: *Image, mgr: *ResourceManager) void {
        if (self.owns_image) self.allocated_image.destroy(mgr.engine);
    }
};

/// Basic placeholder textures created once, at `initBasicTextures`, instead
/// of loaded from a file. `white` and `checker` in particular are used
/// elsewhere as fallbacks (untextured-material default, missing-texture
/// stand-in), so every kind gets a stable id via `basicTextureId` — no
/// lookup by name/path needed, and no risk of colliding with a real asset's
/// derived id.
///
/// Declaration order matters: `initBasicTextures` registers them in this
/// order, and `white` must land in bindless slot 0 (the implicit fallback
/// slot untextured material fields default to).
pub const BasicTexture = enum(u32) {
    white,
    black,
    grey,
    checker,

    // Container-scope `const`, not locals inside `pixels()`: these are
    // comptime-evaluated once and get real static storage duration.
    // Returning `&Color.White.toBytes()` (or `&(y ++ b ++ b ++ y)` built
    // from function-local `const`s) from a function called at runtime
    // instead returns the address of that call's own stack frame — a
    // dangling pointer the instant `pixels()` returns, silently valid or
    // garbage depending on what reuses the stack slot before the caller
    // reads through it. That's what produced garbage bytes for white/grey
    // here while black/checker happened to survive.
    const white_bytes: [4]u8 = Color.White.toBytes();
    const black_bytes: [4]u8 = Color.Black.toBytes();
    const grey_bytes: [4]u8 = Color.Grey.toBytes();
    const checker_bytes: [16]u8 = Color.Yellow.toBytes() ++ Color.Black.toBytes() ++ Color.Black.toBytes() ++ Color.Yellow.toBytes();

    pub fn pixels(self: BasicTexture) []const u8 {
        return switch (self) {
            .white => &white_bytes,
            .black => &black_bytes,
            .grey => &grey_bytes,
            .checker => &checker_bytes,
        };
    }

    pub fn size(self: BasicTexture) u32 {
        return switch (self) {
            .white, .black, .grey => 1,
            .checker => 2,
        };
    }
};
