const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");

vk_pool: vk.DescriptorPool,
vk_descriptor: vk.DescriptorSet,

pub fn createPool(ctx: *GraphicsContext, usage: vk.DescriptorPoolCreateFlags) !vk.DescriptorPool {
    const dpci: vk.DescriptorPoolCreateInfo = .{
        .s_type = .descriptor_pool_create_info,
        .flags = usage,
        .max_sets = 1,
        .pool_size_count = 1,
    };

    // ctx.device.createDescriptorPool(p_create_info: *const DescriptorPoolCreateInfo, p_allocator: ?*const AllocationCallbacks);

}

pub fn createDescriptorSet(ctx: *GraphicsContext) !vk.DescriptorSet {}
