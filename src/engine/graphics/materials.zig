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

pub const MaterialPipeline = struct {
    pipeline: Pipeline,
    pipeline_layout: vk.PipelineLayout,
};

pub const MaterialInstance = struct {
    pipeline: *MaterialPipeline,
    // material_set: vk.DescriptorSet,
    pass_type: MaterialPass,
    buffer_slot_idx: u32,
    material_idx: u32,
};

pub const MaterialPass = enum(u8) {
    MainColor,
    Transparent,
    Other,
};

pub const PBRMaterial = struct {
    opaque_pipeline: MaterialPipeline,
    transparent_pipeline: MaterialPipeline,
    // material_layout: vk.DescriptorSetLayout,

    pub const MaterialConstants = extern struct {
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
        // Pads the record to 80 bytes = the std430 array stride the shader
        // uses for StructuredBuffer<MaterialData> in scene.slang (its float4
        // members give the struct 16-byte alignment, so 76 bytes of fields
        // round up to 80 per element). extern layout + this pad + the asserts
        // below keep the Zig and Slang sides in lockstep at compile time.
        _padding1: u32 = 0,

        comptime {
            if (@offsetOf(MaterialConstants, "color_tex_id") != 52) @compileError("color_tex_id must be at offset 52 (must match MaterialData in scene.slang)");
            if (@sizeOf(MaterialConstants) != 80) @compileError("MaterialConstants must be 80 bytes (std430 stride of MaterialData in scene.slang)");
        }
    };

    pub fn createMaterialPushConstantsBuffer(engine: *const Engine, size: u32) !Buffer {
        return try Buffer.create(engine.ctx, @sizeOf(PBRMaterial.MaterialConstants) * size, .{ .storage_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    }

    pub const MaterialResources = struct {
        color_image: Image,
        color_sampler: Sampler,
        metal_rough_image: Image,
        metal_rough_sampler: Sampler,
        normal_image: Image,
        normal_sampler: Sampler,
        emissive_image: Image,
        emissive_sampler: Sampler,
        occlusion_image: Image,
        occlusion_sampler: Sampler,
        transmission_image: Image,
        transmission_sampler: Sampler,
        // data_buffer: Buffer,
        data_buffer_idx: u32,
        data_buffer_offset: vk.DeviceSize = 0,
    };

    pub fn create() PBRMaterial {
        return .{
            .opaque_pipeline = undefined,
            .transparent_pipeline = undefined,
            // .material_layout = undefined,
        };
    }

    pub fn destroy(self: *PBRMaterial, engine: *Engine) void {
        self.opaque_pipeline.pipeline.destroy(engine.ctx);
        self.transparent_pipeline.pipeline.destroy(engine.ctx);
        engine.ctx.device.destroyPipelineLayout(self.opaque_pipeline.pipeline_layout, null);
        // engine.ctx.device.destroyDescriptorSetLayout(self.material_layout, null);
    }

    pub fn buildPipeline(self: *PBRMaterial, engine: *Engine) !void {
        var vert = try Shader.create(engine, .{ .name = "mesh.spv", .stage = .vertex });
        defer vert.destroy(engine.ctx);
        var frag = try Shader.create(engine, .{ .name = "mesh.spv", .stage = .fragment });
        defer frag.destroy(engine.ctx);

        const matrix_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(Buffers.GPUDrawPushConstants), .stage_flags = .{ .vertex_bit = true, .fragment_bit = true } };

        var layout_builder = try descriptor.LayoutBuilder.init(engine.allocator);
        defer layout_builder.deinit();

        try layout_builder.addBinding(0, .uniform_buffer);

        // self.material_layout = try layout_builder.build(engine.ctx, .{ .vertex_bit = true, .fragment_bit = true }, .{}, null);

        const layouts = [_]vk.DescriptorSetLayout{
            engine.descriptor.vk_global_descriptor_set_layout,
            // self.material_layout,
        };

        const pipeline_layout = try engine.ctx.device.createPipelineLayout(&.{
            .set_layout_count = layouts.len,
            .p_set_layouts = @ptrCast(&layouts),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&matrix_range),
        }, null);
        self.opaque_pipeline.pipeline_layout = pipeline_layout;
        self.transparent_pipeline.pipeline_layout = pipeline_layout;

        var pipeline_builder = try Pipeline.Builder.init(engine.allocator);
        defer pipeline_builder.deinit();

        // build the stage-create-info for both vertex and fragment stages. This lets
        // the pipeline know the shader modules per stage
        try pipeline_builder.setShaders(&vert, &frag);
        pipeline_builder.setInputTopology(.triangle_list);
        pipeline_builder.setPolygonMode(.fill);
        pipeline_builder.setCullMode(vk.CullModeFlags{}, .clockwise);
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
        pipeline_builder.enableDepthTest(.false, .less_or_equal);

        self.transparent_pipeline.pipeline = try pipeline_builder.buildPipeline(engine.ctx);
    }

    pub fn clearResources(self: *PBRMaterial, engine: *Engine) void {
        _ = self;
        _ = engine;
    }

    pub fn createMaterialInstance(
        self: *PBRMaterial,
        pass: MaterialPass,
        material_idx: u32,
        buffer_slot_idx: u32,
    ) MaterialInstance {
        var material_data: MaterialInstance = undefined;

        material_data.pass_type = pass;
        material_data.pipeline = switch (pass) {
            .Transparent => &self.transparent_pipeline,
            .MainColor, .Other => &self.opaque_pipeline,
        };

        material_data.buffer_slot_idx = buffer_slot_idx;
        material_data.material_idx = material_idx;
        return material_data;
    }

    // pub fn writeMaterial(
    //     self: *MetallicRoughness,
    //     engine: *Engine,
    //     pass: MaterialPass,
    //     resources: MaterialResources,
    //     desc_allocator: *descriptor.DescriptorAllocator,
    // ) !MaterialInstance {
    //     var material_data: MaterialInstance = undefined;
    //
    //     material_data.pass_type = pass;
    //     material_data.pipeline = switch (pass) {
    //         .Transparent => &self.transparent_pipeline,
    //         .MainColor, .Other => &self.opaque_pipeline,
    //     };
    //
    //        material_data.material_set = try desc_allocator.allocate(engine.ctx, self.material_layout, null);
    //
    //         log.info("Write material image size: {} bytes", .{resources.color_image.size});
    //         engine.descriptor.writer.clear();
    //         try engine.descriptor.writer.writeBuffer(0, resources.data_buffer, @sizeOf(MaterialConstants), resources.data_buffer_offset, .uniform_buffer);
    //
    //         engine.descriptor.writer.updateSet(engine.ctx, material_data.material_set);
    //
    //         return material_data;
    // }
};
