const std = @import("std");
const log = std.log.scoped(.materials);
const vk = @import("vulkan");
const materials = @import("materials.zig");
const descriptor = @import("../vulkan/descriptor.zig");
const Image = @import("../vulkan/image.zig");
const Sampler = @import("../vulkan/sampler.zig");
const Buffer = @import("../vulkan/buffer.zig");
const Buffers = @import("buffers.zig");
const Shader = @import("../vulkan/shader.zig");
const Pipeline = @import("../vulkan/pipeline.zig");
const Engine = @import("../vulkan/engine.zig");

pub const EffectPipeline = struct {
    pipeline: Pipeline,
    pipeline_layout: vk.PipelineLayout,
};

pub const EffectInstance = struct {
    pipeline: *EffectPipeline,
    material_set: vk.DescriptorSet,
    pass_type: EffectPass,
};

pub const EffectPass = enum(u8) {
    Compute,
};

pub const ComputeEffect = struct {
    effect_pipeline: EffectPipeline,
    // effect_layout: vk.DescriptorSetLayout,

    pub const EffectConstants = struct {
        // color_factors: [4]f32,
        // metal_rough_factors: [4]f32,
        // color_tex_id: u32,
        // metal_rough_tex_id: u32,
        // pad_1: u32 = 0,
        // pad_2: u32 = 0,
        // Padding to 256 bytes (minUniformBufferOffsetAlignment on all target GPUs).
        extra: [16][4]f32 = [_][4]f32{.{ 0, 0, 0, 0 }} ** 16,
    };

    // pub fn createEffectPushConstantsBuffer(engine: *const Engine, size: u32) !Buffer {
    //     return try Buffer.create(engine.ctx, @sizeOf(ComputeEffect.EffectConstants) * size, .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    // }

    pub const EffectResources = struct {
        // color_image: Image,
        // color_sampler: Sampler,
        // metal_rough_image: Image,
        // metal_rough_sampler: Sampler,
        // data_buffer: Buffer,
        // data_buffer_offset: vk.DeviceSize = 0,
    };

    pub fn create() ComputeEffect {
        return .{
            .effect_pipeline = undefined,
            // .effect_layout = undefined,
        };
    }

    pub fn destroy(self: *ComputeEffect, engine: *Engine) void {
        self.effect_pipeline.pipeline.destroy(engine.ctx);
        engine.ctx.device.destroyPipelineLayout(self.effect_pipeline.pipeline_layout, null);
        // engine.ctx.device.destroyDescriptorSetLayout(self.effect_layout, null);
    }

    pub fn buildPipeline(self: *ComputeEffect, engine: *Engine) !void {
        var compute = try Shader.create(engine, .{ .name = "sky.spv", .stage = .compute });
        defer compute.destroy(engine.ctx);

        const pipeline_layout = try engine.ctx.device.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&engine.descriptor.draw_image_descriptor_layout),
            .push_constant_range_count = 0,
            .p_push_constant_ranges = undefined,
        }, null);

        const pipeline = try Pipeline.createComputePipeline(engine.ctx, compute, pipeline_layout);

        self.effect_pipeline = .{ .pipeline = pipeline, .pipeline_layout = pipeline_layout };
    }

    // pub fn writeMaterial(
    //     self: *ComputeEffect,
    //     engine: *Engine,
    //     resources: EffectResources,
    //     desc_allocator: *descriptor.DescriptorAllocator,
    // ) !EffectInstance {
    //     var effect_instance: EffectInstance = undefined;
    //     _ = resources;
    //
    //     effect_instance.pass_type = .Compute;
    //     effect_instance.pipeline = &self.effect_pipeline;
    //
    //     effect_instance.material_set = try desc_allocator.allocate(engine.ctx, self.effect_layout, null);
    //
    //     engine.descriptor.writer.clear();
    //     // try engine.descriptor.writer.writeBuffer(0, resources.data_buffer, @sizeOf(MaterialConstants), resources.data_buffer_offset, .uniform_buffer);
    //
    //     engine.descriptor.writer.updateSet(engine.ctx, effect_instance.material_set);
    //
    //
    //     self.effect_layout .draw_image_descriptor = try desc_allocator.allocate(self.ctx, self.descriptor.draw_image_descriptor_layout, null);
    //
    //     self.descriptor.draw_image_descriptor_layout = try builder.build(self.ctx, .{ .compute_bit = true }, .{}, null);
    //     self.descriptor.draw_image_descriptor = try self.descriptor.desc_allocator.allocate(self.ctx, self.descriptor.draw_image_descriptor_layout, null);
    //
    //     self.descriptor.writer.clear();
    //     try self.descriptor.writer.writeImage(0, self.draw_image, self.samplers.get(.linear), .general, .storage_image);
    //     self.descriptor.writer.updateSet(self.ctx, self.descriptor.draw_image_descriptor);
    //
    //
    //
    //
    //     return effect_instance;
    // }
};
