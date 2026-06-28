// The Sampler is for the Vulkan implementation
const vk = @import("vulkan");

const GraphicsContext = @import("../../core/graphics_context.zig");

const Sampler = @This();

pub const SamplerType = enum { linear, nearest };

pub const SamplerOption = struct {
    min_filter: SamplerType = .nearest,
    mag_filter: SamplerType = .nearest,
    min_lod: f32 = 0,
    max_lod: f32 = 0,
    mipmap_mode: SamplerType = .nearest,
    address_mode_u: vk.SamplerAddressMode = .clamp_to_edge,
    address_mode_v: vk.SamplerAddressMode = .clamp_to_edge,
};

vk_sampler: vk.Sampler,

pub fn destroy(self: *Sampler, ctx: *const GraphicsContext) void {
    ctx.device.destroySampler(self.vk_sampler, null);
}

pub fn create(ctx: *const GraphicsContext, option: SamplerOption) !Sampler {
    const sampler_info = vk.SamplerCreateInfo{
        .flags = .{},
        .mip_lod_bias = 0,
        .min_lod = option.min_lod,
        .max_lod = option.max_lod,
        .mag_filter = switch (option.mag_filter) {
            .nearest => .nearest,
            .linear => .linear,
        },
        .min_filter = switch (option.min_filter) {
            .nearest => .nearest,
            .linear => .linear,
        },
        .address_mode_u = option.address_mode_u,
        .address_mode_v = option.address_mode_v,
        .address_mode_w = .clamp_to_edge,
        .anisotropy_enable = vk.Bool32.false,
        .max_anisotropy = ctx.props.limits.max_sampler_anisotropy,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = vk.Bool32.false,
        .compare_enable = vk.Bool32.false,
        .compare_op = .always,
        .mipmap_mode = switch (option.mipmap_mode) {
            .nearest => .nearest,
            .linear => .linear,
        },
    };

    const vk_sampler = try ctx.device.createSampler(&sampler_info, null);

    return .{
        .vk_sampler = vk_sampler,
    };
}
