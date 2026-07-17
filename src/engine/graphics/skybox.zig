const std = @import("std");
const log = std.log.scoped(.materials);
const vk = @import("vulkan");
const materials = @import("materials.zig");
const descriptor = @import("../vulkan/descriptor.zig");
const ImageMetadata = @import("../vulkan/image.zig").ImageMetadata;
const Sampler = @import("../vulkan/sampler.zig");
const Buffer = @import("../vulkan/buffer.zig");
const Buffers = @import("buffers.zig");
const Shader = @import("../vulkan/shader.zig");
const Pipeline = @import("../vulkan/pipeline.zig");
const Engine = @import("../vulkan/engine.zig");

pub const CubemapPipeline = struct {
    pipeline: Pipeline,
    pipeline_layout: vk.PipelineLayout,
};

pub const CubemapInstance = struct {
    pipeline: *Pipeline,
    pipeline_layout: vk.PipelineLayout,
    descriptor_set: vk.DescriptorSet,
    pass_type: CubemapTexturePass,
};

pub const CubemapTexturePass = enum(u8) {
    Opaque,
    ReflectionLight,
};

pub const CubemapTexture = struct {
    opaque_pipeline: CubemapPipeline,
    light_reflection_pipeline: CubemapPipeline,

    cube_layout: vk.DescriptorSetLayout,

    // pos_x_filename: []const u8,
    // pos_y_filename: []const u8,
    // pos_z_filename: []const u8,
    // neg_x_filename: []const u8,
    // neg_y_filename: []const u8,
    // neg_z_filename: []const u8,

    pub const CubemapResources = struct {
        sampler: Sampler,
        cubemap_image: ImageMetadata,
        data_buffer: Buffer,
        data_buffer_offset: vk.DeviceSize = 0,
    };

    pub const CubemapConstants = struct {
        color_factors: [4]f32,
        metal_rough_factors: [4]f32,
        emissive_factor: [4]f32,
        transmission_factor: f32,
        color_tex_id: u32,
        metal_rough_tex_id: u32,
        normal_tex_id: u32,
        occlusion_tex_id: u32,
        emissive_tex_id: u32,
        transmission_tex_id: u32,
        _padding1: u32 = 0,
        // Padding to 256 bytes (minUniformBufferOffsetAlignment on all target GPUs).
        extra: [11][4]f32 = [_][4]f32{.{ 0, 0, 0, 0 }} ** 11,

        // comptime {
        //     if (@offsetOf(MaterialConstants, "color_tex_id") != 52) @compileError("color_tex_id must be at offset 52 (std140 layout)");
        //     if (@sizeOf(MaterialConstants) != 256) @compileError("MaterialConstants must be 256 bytes");
        // }
    };

    pub fn create() CubemapTexture {
        return .{
            .opaque_pipeline = undefined,
            .light_reflection_pipeline = undefined,
            .cube_layout = undefined,
        };
    }

    pub fn destroy(self: *CubemapTexture, engine: *Engine) void {
        self.opaque_pipeline.pipeline.destroy(engine.ctx);
        self.light_reflection_pipeline.pipeline.destroy(engine.ctx);
        engine.ctx.device.destroyPipelineLayout(self.opaque_pipeline.pipeline_layout, null);
        engine.ctx.device.destroyDescriptorSetLayout(self.cube_layout, null);
    }

    pub fn createSkyboxPushConstantsBuffer(engine: *Engine, size: u32) !Buffer {
        return try Buffer.create(engine, @sizeOf(CubemapConstants) * size, .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    }

    pub fn buildPipeline(self: *CubemapTexture, engine: *Engine) !void {
        var vert = try Shader.create(engine, .{ .name = "skybox.spv", .stage = .vertex });
        defer vert.destroy(engine.ctx);
        var frag = try Shader.create(engine, .{ .name = "skybox.spv", .stage = .fragment });
        defer frag.destroy(engine.ctx);

        const matrix_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(Buffers.GPUDrawPushConstants), .stage_flags = .{ .vertex_bit = true } };

        var layout_builder = try descriptor.LayoutBuilder.init(engine.allocator);
        defer layout_builder.deinit();

        try layout_builder.addBinding(0, .uniform_buffer);

        self.cube_layout = try layout_builder.build(engine.ctx, .{ .vertex_bit = true, .fragment_bit = true }, .{}, null);

        const layouts = [_]vk.DescriptorSetLayout{
            engine.descriptor.vk_global_descriptor_set_layout,
            self.cube_layout,
        };

        const pipeline_layout = try engine.ctx.device.createPipelineLayout(&.{
            .set_layout_count = layouts.len,
            .p_set_layouts = @ptrCast(&layouts),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&matrix_range),
        }, null);
        self.opaque_pipeline.pipeline_layout = pipeline_layout;
        self.light_reflection_pipeline.pipeline_layout = pipeline_layout;

        var pipeline_builder = try Pipeline.Builder.init(engine.allocator);
        defer pipeline_builder.deinit();

        // build the stage-create-info for both vertex and fragment stages. This lets
        // the pipeline know the shader modules per stage
        try pipeline_builder.setShaders(&vert, &frag);
        pipeline_builder.setInputTopology(.triangle_list);
        pipeline_builder.setPolygonMode(.fill);
        pipeline_builder.setCullMode(vk.CullModeFlags{ .front_bit = true }, .counter_clockwise);
        pipeline_builder.setMultisamplingNone();
        pipeline_builder.disableBlending();
        pipeline_builder.enableDepthTest(.true, .less_or_equal);

        // render format
        pipeline_builder.setColorAttachmentFormat(engine.draw_image.format);
        pipeline_builder.setDepthFormat(engine.depth_image.format);

        // Use the layout we created
        pipeline_builder.pipeline_layout = pipeline_layout;

        // Build the pipelines
        self.opaque_pipeline.pipeline = try pipeline_builder.buildPipeline(engine.ctx);

        // Create the transparent variant
        pipeline_builder.enableBlendingAdditive();
        // pipeline_builder.enableBlendingAlphablend();
        // pipeline_builder.enableBlendingPremultipliedAlpha();
        pipeline_builder.enableDepthTest(.true, .less_or_equal);
        pipeline_builder.setCullMode(.{ .back_bit = true }, .counter_clockwise);

        self.light_reflection_pipeline.pipeline = try pipeline_builder.buildPipeline(engine.ctx);
    }

    // pub fn load(self: *CubemapTexture, engine: *Engine, cube_image: *ImageMetadata) !void {
    //     _ = cube_image; // autofix
    //     // try self.buildPipeline(engine);
    //
    //     self.
    // }
    // pub fn bind() void {}

    pub fn writeCubeTexture(
        self: *CubemapTexture,
        engine: *Engine,
        pass: CubemapTexturePass,
        resources: CubemapResources,
        desc_allocator: *descriptor.DescriptorAllocator,
    ) !CubemapInstance {
        var cubemap_data: CubemapInstance = undefined;

        cubemap_data.pass_type = pass;
        cubemap_data.pipeline = switch (pass) {
            .Opaque => &self.opaque_pipeline,
            .ReflectionLight => &self.light_reflection_pipeline,
        };

        cubemap_data.descriptor_set = try desc_allocator.allocate(engine.ctx, self.pipeline_layout, null);

        engine.descriptor.writer.clear();
        try engine.descriptor.writer.writeBuffer(0, resources.data_buffer, @sizeOf(CubemapConstants), resources.data_buffer_offset, .uniform_buffer);

        engine.descriptor.writer.updateSet(engine.ctx, cubemap_data.descriptor_set);

        return cubemap_data;
    }
};
