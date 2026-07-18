const std = @import("std");

const Uuid = @import("uuid");
const Gltf = @import("zgltf").Gltf;

const Sampler = @import("../engine/vulkan/sampler.zig");
const ResourceManager = @import("manager.zig");
const Resource = @import("resource.zig").Resource;
const ResourceId = @import("resource.zig").ResourceId;
const Image = @import("image.zig").Image;
const BasicTexture = @import("image.zig").BasicTexture;

/// Implementation of the Vulkan Texture Resource that is managed by the Resource manager.
///
/// A Texture is the (image, sampler) *pairing* -> one bindless slot. Its own
/// GPU footprint is a single descriptor-array entry; the heavy content lives
/// in a ref-counted Image dependency loaded through the manager, and the
/// sampler is a flyweight from the engine cache.
pub const Texture = struct {
    id: ResourceId,
    name: []const u8,
    source: Source,

    image: *Image = undefined,
    /// Kept to release the Image ref in unload.
    image_id: ResourceId = 0,
    /// Copied from the engine sampler cache — never destroyed here.
    sampler: Sampler = undefined,
    /// Bindless slot in the global 2D texture array (binding 3).
    slot: u32 = 0,

    pub const Source = union(enum) {
        gltf_texture: struct { gltf: *Gltf, texture_idx: u32, guid: Uuid.Uuid },
        /// One of AssetManager's basic placeholder textures (white/black/
        /// grey/checker), generated at `AssetManager.initBasicTextures`
        /// instead of loaded from a glTF file.
        basic: BasicTexture,
    };

    pub fn interface(self: *Texture) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: ResourceId, name: []const u8, source: Source) Texture {
        return .{
            .id = id,
            .name = name,
            .source = source,
        };
    }

    pub fn getId(self: *const Texture) ResourceId {
        return self.id;
    }

    pub fn load(self: *Texture, res_manager: *ResourceManager) !void {
        const engine = res_manager.engine;

        const handle = switch (self.source) {
            .gltf_texture => |s| blk: {
                const gltf_texture = s.gltf.data.textures[s.texture_idx];

                // Sampler: glTF record -> SamplerOption -> engine cache (or default).
                self.sampler = if (gltf_texture.sampler) |sampler_idx|
                    try engine.getSampler(samplerOptionFromGltf(s.gltf.data.samplers[sampler_idx]))
                else
                    try engine.getSampler(.{ .min_filter = .linear, .mag_filter = .linear, .mipmap_mode = .linear, .max_lod = 1000 });

                if (gltf_texture.source) |image_idx| {
                    const img = s.gltf.data.images[image_idx];
                    const image_id = if (img.uri) |uri|
                        ResourceManager.makeId(.{ .content = uri })
                    else
                        ResourceManager.makeId(.{ .local = .{ .file_guid = s.guid, .index = @intCast(image_idx) } });

                    break :blk try res_manager.loadImage(Image.init(image_id, img.name orelse img.uri orelse "embedded", .{
                        .gltf_image = .{ .gltf = s.gltf, .image_idx = @intCast(image_idx) },
                    }));
                } else {
                    // No source image at all: one shared "missing" placeholder
                    // per file — sentinel index collapses every source-less
                    // texture in one glTF onto the same entry, matching prior
                    // behavior.
                    break :blk try res_manager.loadImage(Image.init(ResourceManager.makeId(.{ .local = .{ .file_guid = s.guid, .index = std.math.maxInt(u32) } }), "missing", .missing));
                }
            },
            .basic => |kind| blk: {
                // Nearest, not the gltf-default linear: these are 1x1/2x2
                // solid blocks — sampling should just return the block's
                // color, not blur across a texture that has no useful
                // neighboring texels.
                self.sampler = try engine.getSampler(.{ .min_filter = .nearest, .mag_filter = .nearest, .mipmap_mode = .nearest, .max_lod = 1000 });

                break :blk try res_manager.loadImage(Image.init(self.image_id, @tagName(kind), .{
                    .solid = .{ .pixels = kind.pixels(), .size = kind.size() },
                }));
            },
        };

        self.image = handle.get().?;
        self.image_id = handle._id;

        // The texture's own GPU footprint: one (image view, sampler) pair
        // registered on the bindless array.
        self.slot = try engine.descriptor.registerTexture(self);
    }

    pub fn unload(self: *Texture, res_manager: *ResourceManager) void {
        res_manager.release(Image, self.image_id);
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
