const std = @import("std");
const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");

const Descriptor = @This();

// Create a descriptor pool that will hold 10 sets with 1 image each
const MAX_SETS = 10;

global_allocator: DescriptorAllocator,

// Used in the Compute Shader
vk_draw_image_descriptors: vk.DescriptorSet,
vk_draw_image_descriptor_layout: vk.DescriptorSetLayout,

// TODO: make this more generic ? At the moment it is tailor made for my need
pub fn create(allocator: std.mem.Allocator, ctx: *GraphicsContext) !Descriptor {
    var ratio = [_]DescriptorAllocator.PoolSizeRatio{.{ .vk_type = .storage_image, .ratio = 1 }};

    var desc_allocator = DescriptorAllocator.init(allocator);
    try desc_allocator.createPool(ctx, &ratio, MAX_SETS);

    var builder: DescriptorLayoutBuilder = try .init(allocator);
    defer builder.deinit();

    try builder.addBinding(0, .storage_image);

    const vk_draw_image_descriptor_layout = try builder.build(ctx, .{ .compute_bit = true }, .{}, null);
    const vk_draw_image_descriptors = try desc_allocator.allocate(ctx, vk_draw_image_descriptor_layout);

    return .{
        .global_allocator = desc_allocator,
        .vk_draw_image_descriptor_layout = vk_draw_image_descriptor_layout,
        .vk_draw_image_descriptors = vk_draw_image_descriptors,
    };
}

pub fn destroy(self: *Descriptor, ctx: *GraphicsContext) void {
    self.global_allocator.destroyPool(ctx);
    ctx.device.destroyDescriptorSetLayout(self.vk_draw_image_descriptor_layout, null);
}

pub const DescriptorAllocator = struct {
    pub const PoolSizeRatio = struct {
        vk_type: vk.DescriptorType,
        ratio: f32,
    };

    allocator: std.mem.Allocator,
    vk_pool: vk.DescriptorPool,
    // vk_descriptor: vk.DescriptorSet,

    pub fn init(allocator: std.mem.Allocator) DescriptorAllocator {
        return .{
            .allocator = allocator,
            .vk_pool = undefined,
        };
    }

    pub fn createPool(
        self: *DescriptorAllocator,
        ctx: *GraphicsContext,
        ratios: []PoolSizeRatio,
        max_sets: u32,
    ) !void {
        var pool_sizes = try std.ArrayList(vk.DescriptorPoolSize).initCapacity(self.allocator, ratios.len);

        for (ratios) |ratio| {
            pool_sizes.appendAssumeCapacity(.{
                .type = ratio.vk_type,
                .descriptor_count = @as(u32, @intFromFloat(ratio.ratio)) * max_sets,
            });
        }

        const dpci: vk.DescriptorPoolCreateInfo = .{
            .flags = .{},
            .max_sets = max_sets,
            .pool_size_count = @intCast(pool_sizes.items.len),
            .p_pool_sizes = @ptrCast(pool_sizes.items),
        };

        self.vk_pool = try ctx.device.createDescriptorPool(&dpci, null);
    }

    pub fn allocate(self: *DescriptorAllocator, ctx: *GraphicsContext, layout: vk.DescriptorSetLayout) !vk.DescriptorSet {
        const alloc_info: vk.DescriptorSetAllocateInfo = .{
            .p_next = null,
            .descriptor_pool = self.vk_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = &.{layout},
        };

        var ds: vk.DescriptorSet = undefined;
        try ctx.device.allocateDescriptorSets(&alloc_info, @ptrCast(&ds));

        return ds;
    }

    pub fn clearDescriptors(self: *DescriptorAllocator, ctx: *GraphicsContext) void {
        ctx.device.resetDescriptorPool(self.vk_pool, .{});
    }

    pub fn destroyPool(self: *DescriptorAllocator, ctx: *GraphicsContext) void {
        ctx.device.destroyDescriptorPool(self.vk_pool, null);
    }
};

pub const DescriptorLayoutBuilder = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(vk.DescriptorSetLayoutBinding),

    pub fn init(allocator: std.mem.Allocator) !DescriptorLayoutBuilder {
        return .{ .allocator = allocator, .bindings = try .initCapacity(allocator, 0) };
    }

    pub fn deinit(self: *DescriptorLayoutBuilder) void {
        self.bindings.deinit(self.allocator);
    }

    pub fn clear(self: *DescriptorLayoutBuilder) void {
        self.bindings.clearAndFree(self.allocator);
    }

    pub fn addBinding(self: *DescriptorLayoutBuilder, binding: u32, descriptor_type: vk.DescriptorType) !void {
        const new_binding: vk.DescriptorSetLayoutBinding = .{
            .binding = binding,
            .descriptor_count = 1,
            .stage_flags = .{},
            .descriptor_type = descriptor_type,
        };

        try self.bindings.append(self.allocator, new_binding);
    }

    pub fn build(
        self: *DescriptorLayoutBuilder,
        ctx: *GraphicsContext,
        stages: vk.ShaderStageFlags,
        flags: vk.DescriptorSetLayoutCreateFlags,
        p_next: ?*const anyopaque,
    ) !vk.DescriptorSetLayout {
        for (self.bindings.items) |*binding| {
            binding.stage_flags = stages;
        }

        const info: vk.DescriptorSetLayoutCreateInfo = .{
            .p_bindings = @ptrCast(self.bindings.items),
            .binding_count = @intCast(self.bindings.items.len),
            .flags = flags,
            .p_next = p_next,
        };

        return try ctx.device.createDescriptorSetLayout(&info, null);
    }
};
