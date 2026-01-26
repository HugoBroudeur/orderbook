// The Sampler is for the Vulkan implementation
const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");

const Sampler = @This();

pub const SamplerType = enum { linear, nearest };

vk_sampler: vk.Sampler,

pub fn destroy(self: *Sampler, ctx: *const GraphicsContext) void {
    ctx.device.destroySampler(self.vk_sampler, null);
}

pub fn create(ctx: *const GraphicsContext, sampler_type: SamplerType) !Sampler {
    const sampler_info = switch (sampler_type) {
        .nearest => vk.SamplerCreateInfo{
            .flags = .{},
            .mip_lod_bias = 0,
            .min_lod = 0,
            .max_lod = 0,
            .mag_filter = .nearest,
            .min_filter = .nearest,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .anisotropy_enable = vk.Bool32.false,
            .max_anisotropy = ctx.props.limits.max_sampler_anisotropy,
            .border_color = .int_opaque_black,
            .unnormalized_coordinates = vk.Bool32.false,
            .compare_enable = vk.Bool32.false,
            .compare_op = .always,
            .mipmap_mode = .nearest,
        },

        .linear => vk.SamplerCreateInfo{
            .flags = .{},
            .mip_lod_bias = 0,
            .min_lod = 0,
            .max_lod = 0,
            .mag_filter = .linear,
            .min_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .anisotropy_enable = vk.Bool32.false,
            .max_anisotropy = ctx.props.limits.max_sampler_anisotropy,
            .border_color = .int_opaque_black,
            .unnormalized_coordinates = vk.Bool32.false,
            .compare_enable = vk.Bool32.false,
            .compare_op = .always,
            .mipmap_mode = .linear,
        },
    };

    const vk_sampler = try ctx.device.createSampler(&sampler_info, null);

    return .{
        .vk_sampler = vk_sampler,
    };
}
