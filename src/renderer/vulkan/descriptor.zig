const std = @import("std");
const vk = @import("vulkan");

const Buffer = @import("buffer.zig");
const Image = @import("image.zig");
const Sampler = @import("sampler.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");

const Descriptor = @This();

pub const Allocator = struct {
    pub const MAX_SETS_PER_POOL = 4092;

    pub const PoolSizeRatio = struct {
        vk_type: vk.DescriptorType,
        ratio: f32,
    };

    allocator: std.mem.Allocator,

    ratios: std.ArrayList(PoolSizeRatio),
    full_pools: std.ArrayList(vk.DescriptorPool),
    ready_pools: std.ArrayList(vk.DescriptorPool),
    sets_per_pool: u32,

    pub fn init(allocator: std.mem.Allocator, ctx: *const GraphicsContext, max_sets: u32, pool_ratios: []const PoolSizeRatio) !Allocator {
        var desc_alloc: Allocator = .{
            .allocator = allocator,
            .sets_per_pool = max_sets,
            .ratios = try .initCapacity(allocator, pool_ratios.len),
            .full_pools = try .initCapacity(allocator, 0),
            .ready_pools = try .initCapacity(allocator, 1),
        };

        desc_alloc.ready_pools.appendAssumeCapacity(try desc_alloc.createPool(ctx, max_sets, pool_ratios));
        for (pool_ratios) |ratio| {
            desc_alloc.ratios.appendAssumeCapacity(ratio);
        }

        desc_alloc.sets_per_pool = max_sets * 3 / 2; //grow it next allocation
        return desc_alloc;
    }

    pub fn createPool(
        self: *Allocator,
        ctx: *const GraphicsContext,
        set_count: u32,
        ratios: []const PoolSizeRatio,
    ) !vk.DescriptorPool {
        var pool_sizes = try std.ArrayList(vk.DescriptorPoolSize).initCapacity(self.allocator, ratios.len);
        defer pool_sizes.deinit(self.allocator);

        for (ratios) |ratio| {
            pool_sizes.appendAssumeCapacity(.{
                .type = ratio.vk_type,
                .descriptor_count = @as(u32, @intFromFloat(ratio.ratio)) * set_count,
            });
        }

        const dpci: vk.DescriptorPoolCreateInfo = .{
            .flags = .{},
            .max_sets = set_count,
            .pool_size_count = @intCast(pool_sizes.items.len),
            .p_pool_sizes = @ptrCast(pool_sizes.items),
        };

        return try ctx.device.createDescriptorPool(&dpci, null);
    }

    pub fn getPool(self: *Allocator, ctx: *const GraphicsContext) !vk.DescriptorPool {
        var new_pool: vk.DescriptorPool = undefined;

        if (self.ready_pools.items.len > 0) {
            new_pool = self.ready_pools.pop().?;
        } else {
            new_pool = try self.createPool(ctx, self.sets_per_pool, self.ratios.items);

            self.sets_per_pool = self.sets_per_pool * 3 / 2;
            if (self.sets_per_pool > MAX_SETS_PER_POOL) {
                self.sets_per_pool = MAX_SETS_PER_POOL;
            }
        }

        return new_pool;
    }

    pub fn allocate(
        self: *Allocator,
        ctx: *const GraphicsContext,
        layout: vk.DescriptorSetLayout,
        p_next: ?*const anyopaque,
    ) !vk.DescriptorSet {
        var pool = try self.getPool(ctx);

        var alloc_info: vk.DescriptorSetAllocateInfo = .{
            .p_next = p_next,
            .descriptor_pool = pool,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast(&layout),
        };

        var ds: vk.DescriptorSet = undefined;
        ctx.device.allocateDescriptorSets(&alloc_info, @ptrCast(&ds)) catch {
            // Allocation failed, try again
            try self.full_pools.append(self.allocator, pool);
            pool = try self.getPool(ctx);
            alloc_info.descriptor_pool = pool;
            try ctx.device.allocateDescriptorSets(&alloc_info, @ptrCast(&ds));
        };

        try self.ready_pools.append(self.allocator, pool);
        return ds;
    }

    pub fn clearPools(self: *Allocator, ctx: *const GraphicsContext) !void {
        for (self.ready_pools.items) |pool| {
            try ctx.device.resetDescriptorPool(pool, .{});
        }
        try self.ready_pools.ensureTotalCapacity(self.allocator, self.ready_pools.items.len + self.full_pools.items.len);
        for (self.full_pools.items) |pool| {
            try ctx.device.resetDescriptorPool(pool, .{});
            self.ready_pools.appendAssumeCapacity(pool);
        }
        self.full_pools.clearRetainingCapacity();
    }

    pub fn destroyPools(self: *Allocator, ctx: *const GraphicsContext) void {
        for (self.ready_pools.items) |pool| {
            ctx.device.destroyDescriptorPool(pool, null);
        }
        self.ready_pools.deinit(self.allocator);
        for (self.full_pools.items) |pool| {
            ctx.device.destroyDescriptorPool(pool, null);
        }
        self.full_pools.deinit(self.allocator);
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
        ctx: *const GraphicsContext,
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

pub const DescriptorWriter = struct {
    allocator: std.mem.Allocator,

    image_infos: std.ArrayList(vk.DescriptorImageInfo),
    buffer_infos: std.ArrayList(vk.DescriptorBufferInfo),
    writes: std.ArrayList(vk.WriteDescriptorSet),

    pub fn init(allocator: std.mem.Allocator) !DescriptorWriter {
        return .{
            .image_infos = try .initCapacity(allocator, 0),
            .buffer_infos = try .initCapacity(allocator, 0),
            .writes = try .initCapacity(allocator, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DescriptorWriter) void {
        self.image_infos.deinit(self.allocator);
        self.buffer_infos.deinit(self.allocator);
        self.writes.deinit(self.allocator);
    }

    pub fn writeImage(
        self: *DescriptorWriter,
        binding: u32,
        image: Image,
        layout: vk.ImageLayout,
        descriptor_type: vk.DescriptorType,
    ) !void {
        const image_info = vk.DescriptorImageInfo{
            .sampler = image.sampler.vk_sampler,
            .image_view = image.view,
            .image_layout = layout,
        };
        try self.image_infos.append(self.allocator, image_info);

        const write = vk.WriteDescriptorSet{
            .dst_binding = binding,
            .dst_set = .null_handle, // Will be set in updateSet
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = descriptor_type,
            .p_image_info = @ptrCast(&self.image_infos.items[self.image_infos.items.len - 1]),
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        try self.writes.append(self.allocator, write);
    }

    pub fn writeBuffer(
        self: *DescriptorWriter,
        binding: u32,
        buffer: Buffer,
        size: vk.DeviceSize,
        offset: vk.DeviceSize,
        descriptor_type: vk.DescriptorType,
    ) !void {
        const buffer_info = vk.DescriptorBufferInfo{
            .buffer = buffer.vk_buffer,
            .offset = offset,
            .range = size,
        };
        try self.buffer_infos.append(self.allocator, buffer_info);

        const write = vk.WriteDescriptorSet{
            .dst_binding = binding,
            .dst_set = .null_handle, // Will be set in updateSet
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = descriptor_type,
            .p_image_info = undefined,
            .p_buffer_info = @ptrCast(&self.buffer_infos.items[self.buffer_infos.items.len - 1]),
            .p_texel_buffer_view = undefined,
        };
        try self.writes.append(self.allocator, write);
    }

    pub fn clear(self: *DescriptorWriter) void {
        self.image_infos.clearRetainingCapacity();
        self.buffer_infos.clearRetainingCapacity();
        self.writes.clearRetainingCapacity();
    }

    pub fn updateSet(self: *DescriptorWriter, ctx: *const GraphicsContext, set: vk.DescriptorSet) void {
        // Update all writes to point to the target set
        for (self.writes.items) |*write| {
            write.dst_set = set;
        }

        ctx.device.updateDescriptorSets(
            @intCast(self.writes.items.len),
            self.writes.items.ptr,
            0,
            undefined,
        );
    }
};
