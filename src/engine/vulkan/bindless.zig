const std = @import("std");
const vk = @import("vulkan");

const Engine = @import("engine.zig");

const Texture = @import("../../resource_management/texture.zig").Texture;

const DescriptorAllocator = @import("descriptor.zig").DescriptorAllocator;
const DescriptorWriter = @import("descriptor.zig").DescriptorWriter;
const DescriptorLayoutBuilder = @import("descriptor.zig").LayoutBuilder;

const Buffer = @import("buffer.zig");
const AllocatedImage = @import("image.zig").AllocatedImage;
const Sampler = @import("sampler.zig");

const MaterialConstants = @import("../graphics/materials.zig").PBRMaterial.MaterialConstants;

const Bindless = @This();

pub const Registry = struct {
    // Create a descriptor pool that will hold 10 sets with 1 image each
    const MAX_SETS = 10;
    const DEFAULT_MATERIAL_COUNT = 1024;

    allocator: std.mem.Allocator,
    desc_allocator: DescriptorAllocator,
    writer: DescriptorWriter,

    engine: *Engine,

    // Used in the Compute Shader
    draw_image_descriptor: vk.DescriptorSet = undefined,
    draw_image_descriptor_layout: vk.DescriptorSetLayout = undefined,

    // Global Scene
    vk_global_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

    /// The choice made is to have 1 buffer for all material data
    /// it needs to be managed when a new Material is loaded
    pbr_material_buffer: Buffer = undefined,
    pbr_material_buffer_slot: u32 = 0,
    pbr_material_count: u32 = 0,

    // Bindless texture registry (slot 0 = AssetManager's basic white
    // texture, the implicit fallback untextured material fields default to)
    texture_cache_count: u32 = 0,
    buffer_cache_count: u32 = 0,
    cubemap_cache_count: u32 = 0,
    texture_cache: std.ArrayList(vk.DescriptorImageInfo),
    buffer_cache: std.ArrayList(vk.DescriptorBufferInfo),
    cubemap_cache: std.ArrayList(vk.DescriptorImageInfo),

    pub fn init(engine: *Engine) !Registry {
        var ratio = [_]DescriptorAllocator.PoolSizeRatio{
            .{ .vk_type = .storage_image, .ratio = 3 },
            .{ .vk_type = .uniform_buffer, .ratio = 4 },
            .{ .vk_type = .storage_buffer, .ratio = 128 },
            .{ .vk_type = .combined_image_sampler, .ratio = 4096 },
            // .{ .vk_type = .sampler, .ratio = 1 },
        };
        return .{
            .allocator = engine.allocator,
            .desc_allocator = try DescriptorAllocator.init(engine, MAX_SETS, &ratio),
            .writer = try .init(engine.allocator),

            .texture_cache = .empty,
            .buffer_cache = .empty,
            .cubemap_cache = .empty,

            .engine = engine,
        };
    }
    pub fn destroy(self: *Registry, engine: *Engine) void {
        self.desc_allocator.destroy(engine.ctx);
        self.engine.ctx.device.destroyDescriptorSetLayout(self.draw_image_descriptor_layout, null);
        self.engine.ctx.device.destroyDescriptorSetLayout(self.vk_global_descriptor_set_layout, null);
        self.writer.deinit();

        self.texture_cache.deinit(self.allocator);
        self.buffer_cache.deinit(self.allocator);
        self.cubemap_cache.deinit(self.allocator);
        self.pbr_material_buffer.destroy();
    }

    pub fn setupComputeImageSet(self: *Registry, image: AllocatedImage) !void {
        var builder: DescriptorLayoutBuilder = try .init(self.allocator);
        defer builder.deinit();

        try builder.addBinding(0, .storage_image);

        self.draw_image_descriptor_layout = try builder.build(self.engine.ctx, .{ .compute_bit = true }, .{}, null);
        self.draw_image_descriptor = try self.desc_allocator.allocate(self.engine.ctx, self.draw_image_descriptor_layout, null);

        self.writer.clear();
        try self.writer.writeImage(0, image, self.engine.samplers.get(.linear), .general, .storage_image);
        self.writer.updateSet(self.engine.ctx, self.draw_image_descriptor);
    }

    pub fn setupGlobalSet(self: *Registry) !void {
        var builder = try DescriptorLayoutBuilder.init(self.allocator);
        defer builder.deinit();
        try builder.addBinding(0, .uniform_buffer); // UBO
        try builder.addBinding(1, .combined_image_sampler); // Cube Textures (Skybox)
        try builder.addBinding(2, .storage_buffer); // Data
        try builder.addBinding(3, .combined_image_sampler); // 2D Textures
        builder.bindings.items[1].descriptor_count = 32;
        builder.bindings.items[2].descriptor_count = 1024;
        builder.bindings.items[3].descriptor_count = 4096;

        const flags: [4]vk.DescriptorBindingFlags = .{
            .{},
            .{ .partially_bound_bit = true },
            .{ .partially_bound_bit = true },
            .{ .partially_bound_bit = true, .variable_descriptor_count_bit = true },
        };
        const bind_flags: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
            .binding_count = flags.len,
            .p_binding_flags = @ptrCast(&flags),
        };

        self.vk_global_descriptor_set_layout = try builder.build(
            self.engine.ctx,
            .{ .vertex_bit = true, .fragment_bit = true },
            .{},
            &bind_flags,
        );

        // I have re-enabled the variable count. Previously the layout had
        // 0 - UBO
        // 1 - Textures
        // Variable means textures can grow dynamically
        // If it happers that I need more, I'll need to put that back in place and move
        // the [1] slot to the last one and update all the shaders
        const variable_count: u32 = 4096;
        const variable_count_info: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{
            .descriptor_set_count = 1,
            .p_descriptor_counts = @ptrCast(&variable_count),
        };
        _ = try self.desc_allocator.allocate(
            self.engine.ctx,
            self.vk_global_descriptor_set_layout,
            // null,
            @ptrCast(&variable_count_info),
        );

        // Slot 0 is no longer pre-seeded here: it runs before AssetManager
        // exists, and AssetManager.initBasicTextures (called right after
        // AssetManager.init, before anything else can register a texture)
        // registers `white` first, which claims slot 0 — the same slot
        // untextured material fields implicitly fall back to.
        self.pbr_material_buffer = try self.createMaterialBuffer(DEFAULT_MATERIAL_COUNT);
        self.pbr_material_buffer_slot = try self.registerBuffer(&self.pbr_material_buffer, 0);
    }

    fn createMaterialBuffer(self: *Registry, size: u32) !Buffer {
        return try Buffer.create(
            self.engine,
            @sizeOf(MaterialConstants) * size,
            .{ .storage_buffer_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
        );
    }

    /// Reserve a slot in the shared material buffer and return its index.
    /// Registration only — mirrors registerTexture/registerBuffer: the
    /// caller (Material.upload) writes its own constants into the slot.
    pub fn registerMaterial(self: *Registry) !u32 {
        try self.ensureMaterialCapacity(1);
        const idx = self.pbr_material_count;
        self.pbr_material_count += 1;
        return idx;
    }

    /// Call this function to bind image/sampler to a descriptor set
    pub fn registerTexture(self: *Registry, texture: *const Texture) !u32 {
        return self.registerImageView(texture.image.allocated_image.view, texture.sampler.vk_sampler);
    }

    /// Registers a raw (image view, sampler) pair into the bindless 2D
    /// texture array (binding 3, `allTextures[]`), returning its slot.
    /// For engine-owned images that aren't resource_management assets —
    /// font atlases, render targets — so they don't need a Texture/Image
    /// resource wrapper just to become bindless-addressable.
    pub fn registerImageView(self: *Registry, view: vk.ImageView, sampler: vk.Sampler) !u32 {
        const slot = self.texture_cache_count;
        self.texture_cache_count += 1;
        try self.texture_cache.append(self.allocator, .{
            .sampler = sampler,
            .image_view = view,
            .image_layout = .shader_read_only_optimal,
        });
        return slot;
    }

    /// Call this function to bind a buffer to a descriptor set
    pub fn registerBuffer(self: *Registry, buffer: *const Buffer, offset: u64) !u32 {
        const slot = self.buffer_cache_count;
        self.buffer_cache_count += 1;
        try self.buffer_cache.append(self.allocator, .{
            .buffer = buffer.vk_buffer,
            .offset = offset,
            .range = buffer.size,
        });
        return slot;
    }

    /// Call this function to bind a Cubemap Texture to a descriptor set
    pub fn registerCubemap(self: *Registry, image: *const AllocatedImage, sampler: *const Sampler) !u32 {
        const slot = self.cubemap_cache_count;
        self.cubemap_cache_count += 1;
        try self.cubemap_cache.append(self.allocator, .{
            .sampler = sampler.vk_sampler,
            .image_view = image.view,
            .image_layout = .shader_read_only_optimal,
        });
        return slot;
    }

    pub fn updateBufferSlot(self: *Registry, slot: u32, buffer: *const Buffer, offset: u64) void {
        self.buffer_cache.items[slot] = .{
            .buffer = buffer.vk_buffer,
            .offset = offset,
            .range = buffer.size,
        };
    }

    pub fn writeFrameDescriptorSet(
        self: *Registry,
        frame_descriptor: *DescriptorAllocator,
        scene_data_buffer: Buffer,
    ) !vk.DescriptorSet {

        // See comment about dynamic descriptor count in the global descriptor
        const variable_count: u32 = @intCast(self.texture_cache.items.len);
        const count_info: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{
            .descriptor_set_count = 1,
            .p_descriptor_counts = @ptrCast(&variable_count),
        };
        const descriptor_set = try frame_descriptor.allocate(
            self.engine.ctx,
            self.vk_global_descriptor_set_layout,
            // null,
            @ptrCast(&count_info),
        );

        self.writer.clear();
        try self.writer.writeBuffer(0, scene_data_buffer, scene_data_buffer.size, 0, .uniform_buffer);

        if (self.texture_cache.items.len > 0) {
            const write = vk.WriteDescriptorSet{
                .dst_binding = 3,
                .dst_set = .null_handle, // filled by updateSet
                .dst_array_element = 0,
                .descriptor_count = @intCast(self.texture_cache.items.len),
                .descriptor_type = .combined_image_sampler,
                .p_image_info = self.texture_cache.items.ptr,
                .p_buffer_info = undefined,
                .p_texel_buffer_view = undefined,
            };
            try self.writer.writes.append(self.writer.allocator, write);
        }

        if (self.buffer_cache.items.len > 0) {
            const write = vk.WriteDescriptorSet{
                .dst_binding = 2,
                .dst_set = .null_handle, // filled by updateSet
                .dst_array_element = 0,
                .descriptor_count = @intCast(self.buffer_cache.items.len),
                .descriptor_type = .storage_buffer,
                .p_image_info = undefined,
                .p_buffer_info = self.buffer_cache.items.ptr,
                .p_texel_buffer_view = undefined,
            };
            try self.writer.writes.append(self.writer.allocator, write);
        }

        self.writer.updateSet(self.engine.ctx, descriptor_set);

        return descriptor_set;
    }

    pub fn ensureMaterialCapacity(self: *Registry, additional: u32) !void {
        const capacity: u32 = @intCast(self.pbr_material_buffer.size / @sizeOf(MaterialConstants));
        const needed = self.pbr_material_count + additional;
        if (needed <= capacity) return;

        var new_capacity = capacity;
        while (new_capacity < needed) new_capacity *|= 2; // double like ArrayList growth

        try self.pbr_material_buffer.resize(&self.engine.getCurrentFrame().cmd_pool, new_capacity * @sizeOf(MaterialConstants));
        self.updateBufferSlot(self.pbr_material_buffer_slot, &self.pbr_material_buffer, 0);
    }
};
