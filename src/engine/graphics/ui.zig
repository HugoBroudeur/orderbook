const vk = @import("vulkan");

const Engine = @import("../vulkan/engine.zig");
const Shader = @import("../vulkan/shader.zig");
const Pipeline = @import("../vulkan/pipeline.zig");
const Buffers = @import("buffers.zig");

pub const Ui = struct {
    pipeline: Pipeline,
    pipeline_layout: vk.PipelineLayout,

    pub fn init() Ui {
        return .{
            .pipeline = undefined,
            .pipeline_layout = undefined,
        };
    }

    pub fn destroy(self: *Ui, engine: *Engine) void {
        self.pipeline.destroy(engine.ctx);
        engine.ctx.device.destroyPipelineLayout(self.pipeline_layout, null);
    }

    pub fn buildPipeline(self: *Ui, engine: *Engine) !void {
        var vert = try Shader.create(engine, .{ .name = "ui.spv", .stage = .vertex });
        defer vert.destroy(engine.ctx);
        var frag = try Shader.create(engine, .{ .name = "ui.spv", .stage = .fragment });
        defer frag.destroy(engine.ctx);

        var pipeline_builder = try Pipeline.Builder.init(engine.allocator);
        defer pipeline_builder.deinit();
        try pipeline_builder.setShaders(&vert, &frag);
        pipeline_builder.setInputTopology(.triangle_list);
        pipeline_builder.setPolygonMode(.fill);
        pipeline_builder.setCullMode(.{}, .clockwise);
        pipeline_builder.setMultisamplingNone();
        pipeline_builder.enableBlendingAlphablend(); // UI needs alpha blending (glyph edges, translucent panels)
        pipeline_builder.disableDepthTest();
        pipeline_builder.setColorAttachmentFormat(engine.draw_image.format);
        pipeline_builder.setDepthFormat(.undefined);

        const push_constant_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(Buffers.UIPushConstants), .stage_flags = .{ .vertex_bit = true } };

        const set_layouts = [_]vk.DescriptorSetLayout{
            engine.descriptor.vk_global_descriptor_set_layout, // set 0
            // self.descriptor.vk_material_descriptor_set_layout, // set 1
        };

        const pipeline_layout = try engine.ctx.device.createPipelineLayout(&.{
            .set_layout_count = set_layouts.len,
            .p_set_layouts = @ptrCast(&set_layouts),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&push_constant_range),
        }, null);

        pipeline_builder.pipeline_layout = pipeline_layout;
        const pipeline = try pipeline_builder.buildPipeline(engine.ctx);

        self.pipeline = pipeline;
        self.pipeline_layout = pipeline_layout;
    }
};
