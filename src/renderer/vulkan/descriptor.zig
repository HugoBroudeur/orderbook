const std = @import("std");
const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");

const Descriptor = @This();

pub const Allocator = struct {
    pub const PoolSizeRatio = struct {
        vk_type: vk.DescriptorType,
        ratio: f32,
    };

    allocator: std.mem.Allocator,
    vk_pool: vk.DescriptorPool,
    vk_descriptor_set: vk.DescriptorSet,

    pub fn init(allocator: std.mem.Allocator) Allocator {
        return .{
            .allocator = allocator,
            .vk_pool = undefined,
            .vk_descriptor_set = undefined,
        };
    }

    pub fn createPool(
        self: *Allocator,
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

    pub fn allocate(self: *Allocator, ctx: *GraphicsContext, layout: vk.DescriptorSetLayout) !vk.DescriptorSet {
        const alloc_info: vk.DescriptorSetAllocateInfo = .{
            .p_next = null,
            .descriptor_pool = self.vk_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = &.{layout},
        };

        try ctx.device.allocateDescriptorSets(&alloc_info, @ptrCast(&self.vk_descriptor_set));

        return self.vk_descriptor_set;
    }

    pub fn clearDescriptors(self: *Allocator, ctx: *GraphicsContext) void {
        ctx.device.resetDescriptorPool(self.vk_pool, .{});
    }

    pub fn destroyPool(self: *Allocator, ctx: *GraphicsContext) void {
        ctx.device.destroyDescriptorPool(self.vk_pool, null);
    }
};

pub const LayoutBuilder = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(vk.DescriptorSetLayoutBinding),

    pub fn init(allocator: std.mem.Allocator) !LayoutBuilder {
        return .{ .allocator = allocator, .bindings = try .initCapacity(allocator, 0) };
    }

    pub fn deinit(self: *LayoutBuilder) void {
        self.bindings.deinit(self.allocator);
    }

    pub fn clear(self: *LayoutBuilder) void {
        self.bindings.clearAndFree(self.allocator);
    }

    pub fn addBinding(self: *LayoutBuilder, binding: u32, descriptor_type: vk.DescriptorType) !void {
        const new_binding: vk.DescriptorSetLayoutBinding = .{
            .binding = binding,
            .descriptor_count = 1,
            .stage_flags = .{},
            .descriptor_type = descriptor_type,
        };

        try self.bindings.append(self.allocator, new_binding);
    }

    pub fn build(
        self: *LayoutBuilder,
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
