const std = @import("std");

const AssetManager = @import("manager.zig");
const Resource = @import("resource.zig").Resource;
const Gltf = @import("zgltf").Gltf;

const VulkanImage = @import("../engine/vulkan/image.zig");
const AllocatedImage = VulkanImage.AllocatedImage;
const ImageMetadata = VulkanImage.ImageMetadata;
const ImageDataKind = VulkanImage.ImageDataKind;

/// Implementation of the Vulkan Image Resource that is managed by the Resource manager.
///
/// The Image is the *content* (pixels on the GPU) — identity is the pixel
/// source, independent of samplers. Textures compose it: N textures sharing
/// the same pixels ref-count one Image, so the data uploads once no matter
/// how many (image, sampler) pairings reference it.
pub const Image = struct {
    id: []const u8,
    source: Source,

    allocated_image: AllocatedImage = undefined,
    /// False when load fell back to error_checker (image owned by the engine).
    owns_image: bool = true,

    pub const Source = union(enum) {
        gltf_image: struct { gltf: *Gltf, image_idx: u32 },
        file: []const u8,
        /// glTF texture had no source image -> error_checker fallback.
        missing,
    };

    pub fn interface(self: *Image) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: []const u8, source: Source) Image {
        return .{
            .id = id,
            .source = source,
        };
    }

    pub fn getId(self: *const Image) []const u8 {
        return self.id;
    }

    pub fn load(self: *Image, mgr: *AssetManager) !void {
        const engine = mgr.engine;

        const kind: ?ImageDataKind = switch (self.source) {
            .gltf_image => |s| blk: {
                const img = s.gltf.data.images[s.image_idx];
                if (img.uri) |uri| break :blk .{ .path = uri };
                if (img.data) |d| break :blk .{ .pixels = .{ .data = d } };
                break :blk null;
            },
            .file => |path| .{ .path = path },
            .missing => null,
        };

        if (kind) |k| {
            const meta = ImageMetadata.init(k, null);
            self.allocated_image = try meta.allocateImage(engine, .{ .sampled_bit = true }, true, 1);
            try meta.upload(engine, self.allocated_image);
        } else {
            self.allocated_image = engine.images.get(.error_checker);
            self.owns_image = false;
        }
    }

    pub fn unload(self: *Image, mgr: *AssetManager) void {
        if (self.owns_image) self.allocated_image.destroy(mgr.engine);
    }
};
