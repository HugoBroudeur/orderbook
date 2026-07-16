const std = @import("std");

const Uuid = @import("uuid");
const Gltf = @import("zgltf").Gltf;

const Sampler = @import("../engine/vulkan/sampler.zig");
const AssetManager = @import("manager.zig");
const Resource = @import("resource.zig").Resource;
const Image = @import("image.zig").Image;

/// Implementation of the Vulkan Texture Resource that is managed by the Resource manager.
///
/// A Texture is the (image, sampler) *pairing* -> one bindless slot. Its own
/// GPU footprint is a single descriptor-array entry; the heavy content lives
/// in a ref-counted Image dependency loaded through the manager, and the
/// sampler is a flyweight from the engine cache.
pub const Texture = struct {
    id: []const u8,
    source: Source,

    image: *Image = undefined,
    /// Kept to release the Image ref in unload. Owned by this Texture.
    image_id: []const u8 = "",
    /// Copied from the engine sampler cache — never destroyed here.
    sampler: Sampler = undefined,
    /// Bindless slot in the global 2D texture array (binding 3).
    slot: u32 = 0,

    pub const Source = union(enum) {
        gltf_texture: struct { gltf: *Gltf, texture_idx: u32, guid: Uuid.Uuid },
    };

    pub fn interface(self: *Texture) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: []const u8, source: Source) Texture {
        return .{
            .id = id,
            .source = source,
        };
    }

    pub fn getId(self: *const Texture) []const u8 {
        return self.id;
    }

    pub fn load(self: *Texture, mgr: *AssetManager) !void {
        const engine = mgr.engine;
        const s = self.source.gltf_texture;
        const gltf_texture = s.gltf.data.textures[s.texture_idx];

        // Sampler: glTF record -> SamplerOption -> engine cache (or default).
        self.sampler = if (gltf_texture.sampler) |sampler_idx|
            try engine.getSampler(samplerOptionFromGltf(s.gltf.data.samplers[sampler_idx]))
        else
            engine.samplers.get(.linear);

        // Image: ref-counted composition. Identity is sampler-independent,
        // so N textures sharing pixels -> one upload, ref_count = N.
        if (gltf_texture.source) |image_idx| {
            self.image_id = try imageId(mgr.allocator, s.gltf, @intCast(image_idx), s.guid);
            const handle = try mgr.loadImage(Image.init(self.image_id, .{
                .gltf_image = .{ .gltf = s.gltf, .image_idx = @intCast(image_idx) },
            }));
            self.image = handle.get().?;
        } else {
            self.image_id = try std.fmt.allocPrint(mgr.allocator, "{x}#missing", .{s.guid});
            const handle = try mgr.loadImage(Image.init(self.image_id, .missing));
            self.image = handle.get().?;
        }

        // The texture's own GPU footprint: one (image view, sampler) pair
        // registered on the bindless array.
        self.slot = try engine.descriptor.registerTexture(&self.image.allocated_image, &self.sampler);
    }

    pub fn unload(self: *Texture, mgr: *AssetManager) void {
        mgr.release(Image, self.image_id);
        mgr.allocator.free(self.image_id);
        // sampler: cache-owned. slot: append-only registry, not reclaimed
        // (same accepted limitation as material slots).
    }

    /// URI when the image is file-backed (dedupes across glTF files that
    /// reference the same texture file); guid#img{idx} for embedded images
    /// (file-local — no cross-file identity exists to exploit).
    fn imageId(allocator: std.mem.Allocator, gltf: *Gltf, image_idx: u32, guid: Uuid.Uuid) ![]const u8 {
        const img = gltf.data.images[image_idx];
        return if (img.uri) |uri|
            try allocator.dupe(u8, uri)
        else
            try std.fmt.allocPrint(allocator, "{x}#img{d}", .{ guid, image_idx });
    }

    fn samplerOptionFromGltf(samp: Gltf.TextureSampler) Sampler.SamplerOption {
        const mag_filter = extractFilter(samp.mag_filter orelse .nearest);
        const mipmap_mode = extractMipmapMode(samp.min_filter orelse .nearest);

        return .{
            .min_filter = mipmap_mode,
            .mag_filter = mag_filter,
            .mipmap_mode = mipmap_mode,
            .max_lod = 1000,
            .min_lod = 0,
            .address_mode_u = switch (samp.wrap_s) {
                .clamp_to_edge => .clamp_to_edge,
                .repeat => .repeat,
                .mirrored_repeat => .mirrored_repeat,
            },
            .address_mode_v = switch (samp.wrap_t) {
                .clamp_to_edge => .clamp_to_edge,
                .repeat => .repeat,
                .mirrored_repeat => .mirrored_repeat,
            },
        };
    }

    fn extractFilter(filter: Gltf.MagFilter) Sampler.SamplerType {
        return switch (filter) {
            .linear => .linear,
            .nearest => .nearest,
        };
    }

    fn extractMipmapMode(filter: Gltf.MinFilter) Sampler.SamplerType {
        return switch (filter) {
            .linear, .linear_mipmap_linear, .nearest_mipmap_linear => .linear,
            .nearest, .nearest_mipmap_nearest, .linear_mipmap_nearest => .nearest,
        };
    }
};
