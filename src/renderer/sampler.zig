// The Sampler is for the SDL implementation
const sdl = @import("sdl3");

const GPU = @import("gpu.zig");

const Sampler = @This();

pub const SamplerType = enum { linear, nearest };

gpu: *GPU,
ptr: sdl.gpu.Sampler = undefined,
is_in_gpu: bool = false,

pub fn init(gpu: *GPU) Sampler {
    return .{ .gpu = gpu };
}

pub fn deinit(self: *Sampler) void {
    self.destroy();
}

pub fn destroy(self: *Sampler) void {
    if (self.is_in_gpu) {
        self.gpu.device.releaseSampler(self.ptr);
        self.is_in_gpu = false;
        self.ptr = undefined;
    }
}

pub fn create(self: *Sampler, sampler_type: SamplerType) !void {
    switch (sampler_type) {
        .nearest => {
            self.ptr = try self.gpu.device.createSampler(.{
                .mipmap_mode = .nearest,
                .address_mode_u = .clamp_to_edge,
                .address_mode_v = .clamp_to_edge,
                .address_mode_w = .clamp_to_edge,
                .min_filter = .nearest,
                .mag_filter = .nearest,
            });
        },
        .linear => {
            self.ptr = try self.gpu.device.createSampler(.{
                .mipmap_mode = .linear,
                .min_filter = .linear,
                .mag_filter = .linear,
                .address_mode_u = .clamp_to_edge,
                .address_mode_v = .clamp_to_edge,
                .address_mode_w = .clamp_to_edge,
            });
        },
    }

    self.is_in_gpu = true;
}

pub fn createWithGpu(gpu: *GPU, sampler_type: SamplerType) !Sampler {
    const ptr = switch (sampler_type) {
        .nearest => try gpu.device.createSampler(.{
            .mipmap_mode = .nearest,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .min_filter = .nearest,
            .mag_filter = .nearest,
        }),
        .linear => try gpu.device.createSampler(.{
            .mipmap_mode = .linear,
            .min_filter = .linear,
            .mag_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        }),
    };

    return .{ .gpu = gpu, .is_in_gpu = true, .ptr = ptr };
}
