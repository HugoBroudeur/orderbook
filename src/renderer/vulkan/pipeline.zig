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
