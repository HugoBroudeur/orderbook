// The Pipeline is for the Vulkan implementation

const std = @import("std");
const log = std.log.scoped(.Pipeline);
const sdl = @import("sdl3");
const vk = @import("vulkan");
const zm = @import("zmath");

const GraphicsContext = @import("../../core/graphics_context.zig");
const Buffer = @import("buffer.zig");
const Shader = @import("shader.zig");
const Data = @import("../data.zig");
const GPU = @import("gpu.zig");
const RenderPass = @import("render_pass.zig");

const MAX_VERTEX_ATTRIBUTES = 20;

const CreateShaderParam = struct {
    shader_name: []const u8,
    uniforms: u32,
    samplers: u32,
};

const Pipeline = @This();

layout: vk.PipelineLayout,
vk_pipeline: vk.Pipeline,

pub const GraphicPipelineInfo = struct {
    pipeline: sdl.gpu.GraphicsPipeline,
    vertex_size: u32,
    index_size: u32,
};

pub fn destroy(self: *Pipeline, ctx: *GraphicsContext) void {
    ctx.device.destroyPipelineLayout(self.layout, null);
    ctx.device.destroyPipeline(self.vk_pipeline, null);
}

pub const CreatePipelineDesc = struct {
    vert: []const u8,
    frag: []const u8,
    layout: Buffer.BufferLayout,
    config: PipelineConfig = .{},
};

pub const PipelineConfig = struct {
    num_push_constant: u32 = 0,
    num_layouts: u32 = 0,
    num_sampler: u32 = 0,
};

pub fn create(ctx: *GraphicsContext, desc: CreatePipelineDesc, render_pass: RenderPass) !Pipeline {
    log.debug("Create pipeline for shader {s} / {s}", .{ desc.vert, desc.frag });
    const pipeline_layout = try createPipelineLayout(ctx);

    var vert = try Shader.create(ctx, .{ .name = desc.vert, .stage = .vertex });
    defer vert.destroy(ctx);
    var frag = try Shader.create(ctx, .{ .name = desc.frag, .stage = .fragment });
    defer frag.destroy(ctx);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        vert.getPipelineShaderStageCreateInfo(),
        frag.getPipelineShaderStageCreateInfo(),
    };

    var vatds = try getVertexInputAttributeDescriptions(desc.layout);
    var vibds = getVertexInputBindingDescriptions(desc.layout);

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&vibds),
        .vertex_attribute_description_count = @intCast(desc.layout.elements.len),
        .p_vertex_attribute_descriptions = &vatds,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = if (desc.config.num_sampler == 0) .false else .true,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = pipeline_layout,
        .render_pass = render_pass.vk_render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try ctx.device.createGraphicsPipelines(
        .null_handle,
        1,
        @ptrCast(&gpci),
        null,
        @ptrCast(&pipeline),
    );

    return .{ .layout = pipeline_layout, .vk_pipeline = pipeline };

    // ---------------------------------------------------------------------

    // var pipeline_create_info: sdl.gpu.GraphicsPipelineCreateInfo = .{
    //     .vertex_shader = desc.vertex_shader.ptr,
    //     .fragment_shader = desc.fragment_shader.ptr,
    //     .primitive_type = .triangle_list,
    //     .target_info = .{
    //         .color_target_descriptions = &.{.{ .format = desc.texture_format.ptr }},
    //     },
    // };
    //
    // if (desc.vertex_input_state) |vis| {
    //     pipeline_create_info.vertex_input_state = vis;
    // }
    //
    // if (desc.layout) |layout| {
    //     var attributes: [MAX_VERTEX_ATTRIBUTES]sdl.gpu.VertexAttribute = undefined;
    //     var count: u32 = 0;
    //
    //     for (layout.getElements(), 0..) |el, i| {
    //         if (i >= MAX_VERTEX_ATTRIBUTES) return error.TooManyVertexAttributes;
    //         if (el.data_type.toSdl()) |format| {
    //             attributes[count] = .{
    //                 .buffer_slot = 0,
    //                 .format = format,
    //                 .location = count,
    //                 .offset = el.offset,
    //             };
    //             count += 1;
    //         }
    //     }
    //
    //     pipeline_create_info.vertex_input_state = .{
    //         .vertex_buffer_descriptions = &[_]sdl.gpu.VertexBufferDescription{
    //             .{
    //                 .slot = 0,
    //                 .pitch = layout.getStride(),
    //                 .input_rate = .vertex,
    //             },
    //         },
    //         .vertex_attributes = attributes[0..count],
    //     };
    // }
    //
    // const ptr = try gpu.device.createGraphicsPipeline(pipeline_create_info);
    // return .{ .gpu = gpu, .ptr = ptr };
}

fn createPipelineLayout(ctx: *GraphicsContext) !vk.PipelineLayout {
    return try ctx.device.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
}

fn getVertexInputAttributeDescriptions(layout: Buffer.BufferLayout) ![MAX_VERTEX_ATTRIBUTES]vk.VertexInputAttributeDescription {
    var vertex_input_attribute_descriptions: [MAX_VERTEX_ATTRIBUTES]vk.VertexInputAttributeDescription = undefined;
    var count: u32 = 0;

    for (layout.elements, 0..) |element, i| {
        if (i >= MAX_VERTEX_ATTRIBUTES) return error.TooManyVertexAttributes;
        vertex_input_attribute_descriptions[i] = .{
            .location = count,
            .binding = 0,
            .format = element.data_type.toVulkan(),
            .offset = element.offset,
        };
        count += 1;
    }

    return vertex_input_attribute_descriptions;
}

fn getVertexInputBindingDescriptions(layout: Buffer.BufferLayout) vk.VertexInputBindingDescription {
    return .{ .binding = 0, .input_rate = .vertex, .stride = layout.stride };
}

pub const Builder = struct {
    allocator: std.mem.Allocator,

    shader_stages: std.ArrayList(vk.PipelineShaderStageCreateInfo),

    input_assembly: vk.PipelineInputAssemblyStateCreateInfo,
    rasterizer: vk.PipelineRasterizationStateCreateInfo,
    color_blend_attachment: vk.PipelineColorBlendAttachmentState,
    multisampling: vk.PipelineMultisampleStateCreateInfo,
    pipeline_layout: vk.PipelineLayout,
    depth_stencil: vk.PipelineDepthStencilStateCreateInfo,
    render_info: vk.PipelineRenderingCreateInfo,
    color_attachment_format: vk.Format,

    pub fn init(allocator: std.mem.Allocator) !Builder {
        var builder = Builder{
            .allocator = allocator,
            .shader_stages = try std.ArrayList(vk.PipelineShaderStageCreateInfo).initCapacity(allocator, 0),
            .input_assembly = undefined,
            .rasterizer = undefined,
            .color_blend_attachment = undefined,
            .multisampling = undefined,
            .pipeline_layout = .null_handle,
            .depth_stencil = undefined,
            .render_info = undefined,
            .color_attachment_format = .undefined,
        };
        builder.clear();
        return builder;
    }

    pub fn deinit(self: *Builder) void {
        self.shader_stages.deinit();
    }

    pub fn clear(self: *Builder) void {
        self.pipeline_layout = .null_handle;
        self.shader_stages.clearAndFree(self.allocator);

        self.input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

        self.rasterizer = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        };

        self.multisampling = vk.PipelineMultisampleStateCreateInfo{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

        self.color_blend_attachment = vk.PipelineColorBlendAttachmentState{
            .blend_enable = .false,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };
        self.depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
            .depth_test_enable = .false,
            .depth_write_enable = .false,
            .depth_compare_op = .never,
            .depth_bounds_test_enable = .false,
            .stencil_test_enable = .false,
            .front = .{
                .compare_op = .never,
                .pass_op = .zero,
                .fail_op = .zero,
                .depth_fail_op = .zero,
                .compare_mask = 0,
                .reference = 0,
                .write_mask = 0,
            },
            .back = .{
                .compare_op = .never,
                .pass_op = .zero,
                .fail_op = .zero,
                .depth_fail_op = .zero,
                .compare_mask = 0,
                .reference = 0,
                .write_mask = 0,
            },
            .min_depth_bounds = 0,
            .max_depth_bounds = 0,
        };

        self.render_info = vk.PipelineRenderingCreateInfo{
            .view_mask = 0,
            .depth_attachment_format = .undefined,
            .stencil_attachment_format = .undefined,
            .p_color_attachment_formats = null,
        };
    }

    pub fn buildPipeline(
        self: *Builder,
        ctx: *const GraphicsContext,
    ) !Pipeline {
        // viewport state (dynamic viewport + scissor)
        var viewport_state = vk.PipelineViewportStateCreateInfo{
            .s_type = .pipeline_viewport_state_create_info,
            .p_next = null,
            .flags = .{},
            .viewport_count = 1,
            .p_viewports = null, // dynamic
            .scissor_count = 1,
            .p_scissors = null, // dynamic
        };

        // color blending
        var color_blending = vk.PipelineColorBlendStateCreateInfo{
            .s_type = .pipeline_color_blend_state_create_info,
            .p_next = null,
            .flags = .{},
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &.{self.color_blend_attachment},
            .blend_constants = .{ 0, 0, 0, 0 },
        };

        // const pipeline_layout = try createPipelineLayout(ctx);
        // const pssci = [_]vk.PipelineShaderStageCreateInfo{
        //     vert.getPipelineShaderStageCreateInfo(),
        //     frag.getPipelineShaderStageCreateInfo(),
        // };
        //
        // var vatds = try getVertexInputAttributeDescriptions(desc.layout);
        // var vibds = getVertexInputBindingDescriptions(desc.layout);

        // const pvisci = vk.PipelineVertexInputStateCreateInfo{
        //     .vertex_binding_description_count = 1,
        //     .p_vertex_binding_descriptions = @ptrCast(&vibds),
        //     .vertex_attribute_description_count = @intCast(desc.layout.elements.len),
        //     .p_vertex_attribute_descriptions = &vatds,
        // };

        // vertex input (empty)
        var vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = 0,
            .p_vertex_binding_descriptions = null,
            .vertex_attribute_description_count = 0,
            .p_vertex_attribute_descriptions = null,
        };

        // dynamic states
        const dynamic_states = [_]vk.DynamicState{
            .viewport,
            .scissor,
        };

        var dynamic_info = vk.PipelineDynamicStateCreateInfo{
            .s_type = .pipeline_dynamic_state_create_info,
            .p_next = null,
            .flags = .{},
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        };

        // graphics pipeline
        var pipeline_info = vk.GraphicsPipelineCreateInfo{
            .p_next = &self.render_info, // dynamic rendering
            .flags = .{},
            .stage_count = @intCast(self.shader_stages.items.len),
            .p_stages = self.shader_stages.items.ptr,
            .p_vertex_input_state = &vertex_input_info,
            .p_input_assembly_state = &self.input_assembly,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &self.rasterizer,
            .p_multisample_state = &self.multisampling,
            .p_depth_stencil_state = &self.depth_stencil,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = &dynamic_info,
            .layout = self.pipeline_layout,
            .render_pass = .null_handle,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        // var pipeline: vk.Pipeline = vk.NULL_HANDLE;

        var pipeline: vk.Pipeline = undefined;
        _ = try ctx.device.createGraphicsPipelines(
            .null_handle,
            1,
            @ptrCast(&pipeline_info),
            null,
            @ptrCast(&pipeline),
        );

        return .{ .layout = self.pipeline_layout, .vk_pipeline = pipeline };
    }

    pub fn setShaders(self: *Builder, vertex_shader: *const Shader, fragment_shader: *const Shader) !void {
        self.shader_stages.clearAndFree(self.allocator);
        try self.shader_stages.append(self.allocator, vertex_shader.getPipelineShaderStageCreateInfo());
        try self.shader_stages.append(self.allocator, fragment_shader.getPipelineShaderStageCreateInfo());
    }

    pub fn setInputTopology(self: *Builder, topology: vk.PrimitiveTopology) void {
        self.input_assembly.topology = topology;
        self.input_assembly.primitive_restart_enable = vk.FALSE;
    }

    pub fn setPolygonMode(self: *Builder, mode: vk.PolygonMode) void {
        self.rasterizer.polygon_mode = mode;
        self.rasterizer.line_width = 1.0;
    }

    pub fn setCullMode(
        self: *Builder,
        cull: vk.CullModeFlags,
        front_face: vk.FrontFace,
    ) void {
        self.rasterizer.cull_mode = cull;
        self.rasterizer.front_face = front_face;
    }

    pub fn setMultisamplingNone(self: *Builder) void {
        self.multisampling.sample_shading_enable = vk.FALSE;
        self.multisampling.rasterization_samples = .@"1_bit";
        self.multisampling.min_sample_shading = 1.0;
        self.multisampling.p_sample_mask = null;
        self.multisampling.alpha_to_coverage_enable = vk.FALSE;
        self.multisampling.alpha_to_one_enable = vk.FALSE;
    }

    pub fn disableBlending(self: *Builder) void {
        self.color_blend_attachment.color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true };
        self.color_blend_attachment.blend_enable = vk.FALSE;
    }

    pub fn enableBlendingAdditive(self: *Builder) void {
        self.color_blend_attachment.color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true };
        self.color_blend_attachment.blend_enable = vk.TRUE;
        self.color_blend_attachment.src_color_blend_factor = .src_alpha;
        self.color_blend_attachment.dst_color_blend_factor = .one;
        self.color_blend_attachment.color_blend_op = .add;
        self.color_blend_attachment.src_alpha_blend_factor = .one;
        self.color_blend_attachment.dst_alpha_blend_factor = .zero;
        self.color_blend_attachment.alpha_blend_op = .add;
    }

    pub fn enableBlendingAlphablend(self: *Builder) void {
        self.color_blend_attachment.color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true };
        self.color_blend_attachment.blend_enable = vk.TRUE;
        self.color_blend_attachment.src_color_blend_factor = .src_alpha;
        self.color_blend_attachment.dst_color_blend_factor = .one_minus_src_alpha;
        self.color_blend_attachment.color_blend_op = .add;
        self.color_blend_attachment.src_alpha_blend_factor = .one;
        self.color_blend_attachment.dst_alpha_blend_factor = .zero;
        self.color_blend_attachment.alpha_blend_op = .add;
    }

    pub fn setColorAttachmentFormat(self: *Builder, format: vk.Format) void {
        self.color_attachment_format = format;
        self.render_info.color_attachment_count = 1;
        self.render_info.p_color_attachment_formats = @ptrCast(&self.color_attachment_format);
    }

    pub fn setDepthFormat(self: *Builder, format: vk.Format) void {
        self.render_info.depth_attachment_format = format;
    }

    // pub fn setLayout(self: *Builder, layout: Buffer.BufferLayout) void {}

    pub fn disableDepthTest(self: *Builder) void {
        self.depth_stencil.depth_test_enable = vk.FALSE;
        self.depth_stencil.depth_write_enable = vk.FALSE;
        self.depth_stencil.depth_compare_op = .never;
        self.depth_stencil.depth_bounds_test_enable = vk.FALSE;
        self.depth_stencil.stencil_test_enable = vk.FALSE;
        self.depth_stencil.front = .{};
        self.depth_stencil.back = .{};
        self.depth_stencil.min_depth_bounds = 0.0;
        self.depth_stencil.max_depth_bounds = 1.0;
    }

    pub fn enableDepthTest(
        self: *Builder,
        depth_write: vk.Bool32,
        op: vk.CompareOp,
    ) void {
        self.depth_stencil.depth_test_enable = vk.TRUE;
        self.depth_stencil.depth_write_enable = depth_write;
        self.depth_stencil.depth_compare_op = op;
        self.depth_stencil.depth_bounds_test_enable = vk.FALSE;
        self.depth_stencil.stencil_test_enable = vk.FALSE;
        self.depth_stencil.front = .{};
        self.depth_stencil.back = .{};
        self.depth_stencil.min_depth_bounds = 0.0;
        self.depth_stencil.max_depth_bounds = 1.0;
    }

    // pub fn setLayout(self: *Builder, layout: Buffer.BufferLayout) void {
    //     self.layout = layout;
    //     self.vertex_attributes = try getVertexInputAttributeDescriptions(layout);
    //     self.vertex_bindings = getVertexInputBindingDescriptions(layout);
    //
    // }
};
