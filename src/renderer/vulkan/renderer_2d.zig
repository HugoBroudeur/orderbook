// This is a 2D Renderer for the SDL implementation

const std = @import("std");
const log = std.log.scoped(.Renderer2D);
const assert = std.debug.assert;
const sdl = @import("sdl3");
const vk = @import("vulkan");
const tracy = @import("tracy");

const zm = @import("zmath");

const UiManager = @import("../../game/ui_manager.zig");
const EcsManager = @import("../../game/ecs_manager.zig");
const Colors = @import("../../game/colors.zig");

// const Api = @import("../backend.zig").Vulkan;
// const Api = @import("../gfx.zig").Backend(.vulkan);
const Asset = @import("asset.zig");
const Batcher = @import("batcher.zig");
const Buffer = @import("buffer.zig");
const Camera = @import("../camera.zig");
const Command = @import("../command.zig");
const CommandPool = @import("command_pool.zig");
const Data = @import("../data.zig");
const Descriptor = @import("descriptor.zig");
const Framebuffer = @import("framebuffer.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");
const Image = @import("image.zig");
const Logger = @import("../../core/log.zig").MaxLogs(50);
const Mesh = @import("mesh.zig");
const Pipeline = @import("pipeline.zig");
const RenderPass = @import("render_pass.zig");
const Sampler = @import("sampler.zig");
const Shader = @import("shader.zig");
const Stats = @import("../stats.zig");
const Swapchain = @import("swapchain.zig").Swapchain;

const Renderer = @This();

pub const GPUCommandFn = fn (vk.CommandBuffer) anyerror!void;
pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const ImageType = enum { atlas, draw };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { triangle, compute, mesh };

pub const FRAME_OVERLAP = 2;

const Uniforms = struct {
    transform: struct {
        scale: @Vector(2, f32),
        translate: @Vector(2, f32),
    },
    mvp: struct {
        proj_matrix: zm.Mat,
        view_matrix: zm.Mat,
    },
    time: struct {
        time: f32,
    },
};

const FrameData = struct {
    clear_color: vk.ClearValue = .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
    previous_frame_window_size: struct { width: u32, height: u32 } = .{ .width = 0, .height = 0 },
    /// Contains the state if the last swapchain got an error
    swapchain_state: Swapchain.PresentState = .optimal,
    viewport: vk.Viewport = .{ .x = 0, .y = 0, .width = 0, .height = 0, .min_depth = 0, .max_depth = 1 },
    scissor: vk.Rect2D = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .height = 0, .width = 0 } },

    cmd_pool: CommandPool = undefined,
    cmd_buf: vk.CommandBuffer = undefined,

    desc_allocator: Descriptor.Allocator,

    pub fn setup(self: *FrameData, ctx: *GraphicsContext) !void {
        self.cmd_pool = try CommandPool.create(ctx);
        try self.createCommandBuffer(ctx);
    }

    pub fn createCommandBuffer(self: *FrameData, ctx: *GraphicsContext) !void {
        try ctx.device.allocateCommandBuffers(&.{
            .command_pool = self.cmd_pool.vk_cmd_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&self.cmd_buf));
        errdefer ctx.devive.freeCommandBuffers(self.cmd_pool.vk_cmd_pool, 1, @ptrCast(&self.cmd_buf));
    }

    pub fn shouldReset(self: *FrameData, ctx: *const GraphicsContext) bool {
        if (self.swapchain_state == .suboptimal) return true;

        if (self.previous_frame_window_size.height != ctx.window.getHeight()) return true;
        if (self.previous_frame_window_size.width != ctx.window.getWidth()) return true;

        return false;
    }

    pub fn reset(self: *FrameData, ctx: *GraphicsContext, extent: vk.Extent2D) !void {

        // Set Viewport + scisors
        self.viewport.width = @floatFromInt(extent.width);
        self.viewport.height = @floatFromInt(extent.height);
        self.scissor.extent = extent;
        self.previous_frame_window_size = .{ .width = @intCast(ctx.window.getWidth()), .height = @intCast(ctx.window.getHeight()) };

        try self.createCommandBuffer(ctx);
    }

    pub fn destroy(self: *FrameData, ctx: *GraphicsContext) void {
        self.cmd_pool.destroy(ctx);
    }
};

const GlobalDescriptor = struct {

    // Create a descriptor pool that will hold 10 sets with 1 image each
    const MAX_SETS = 10;

    // Used in the Compute Shader
    vk_compute_descriptor_set: vk.DescriptorSet,
    vk_compute_descriptor_set_layout: vk.DescriptorSetLayout,

    // Used in the Mesh Shader
    vk_mesh_descriptor_set: vk.DescriptorSet,
    vk_mesh_descriptor_set_layout: vk.DescriptorSetLayout,

    pub fn create(allocator: std.mem.Allocator, ctx: *GraphicsContext) !GlobalDescriptor {
        var global_descriptor: GlobalDescriptor = undefined;

        var ratio = [_]Descriptor.Allocator.PoolSizeRatio{
            .{ .vk_type = .storage_image, .ratio = 1 },
            .{ .vk_type = .uniform_buffer, .ratio = 1 },
        };

        var desc_allocator = Descriptor.Allocator.init(allocator, ctx, MAX_SETS, &ratio);
        try desc_allocator.createPool(ctx, &ratio, MAX_SETS);

        {
            var builder: Descriptor.LayoutBuilder = try .init(allocator);
            defer builder.deinit();

            try builder.addBinding(0, .storage_image);

            global_descriptor.vk_compute_descriptor_set_layout = try builder.build(ctx, .{ .compute_bit = true }, .{}, null);
            global_descriptor.vk_compute_descriptor_set = try desc_allocator.allocate(ctx, global_descriptor.vk_compute_descriptor_set_layout);
        }
        {
            var mesh_desc_builder = try Descriptor.LayoutBuilder.init(allocator);
            defer mesh_desc_builder.deinit();
            try mesh_desc_builder.addBinding(1, .storage_texel_buffer);
            try mesh_desc_builder.addBinding(2, .sampler);
            global_descriptor.vk_mesh_descriptor_set_layout = try mesh_desc_builder.build(ctx, .{ .fragment_bit = true }, .{}, null);
            global_descriptor.vk_mesh_descriptor_set = try desc_allocator.allocate(ctx, vk_mesh_descriptor_set_layout);
        }
        {
            const writer = try Descriptor.DescriptorWriter.init(self.allocator);
            defer writer.deinit();

            try writer.writeImage(0, draw_image, .general, .storage_image);
            writer.updateSet(self.ctx, self.descriptor.vk_compute_descriptor_set);

            // var img_info = draw_image.createDescriptorImageInfo();
            // const draw_image_write: vk.WriteDescriptorSet = .{
            //     .descriptor_count = 1,
            //     .descriptor_type = .storage_image,
            //     .dst_binding = 0,
            //     .dst_set = self.descriptor.vk_compute_descriptor_set,
            //     .dst_array_element = 0,
            //     .p_image_info = @ptrCast(&img_info), // Only 1 type of pointer can be used
            //     .p_buffer_info = undefined,
            //     .p_texel_buffer_view = undefined,
            // };
            //
            // self.ctx.device.updateDescriptorSets(1, &.{draw_image_write}, 0, null);
        }

        return global_descriptor;

        return .{
            .vk_compute_descriptor_set_layout = vk_compute_descriptor_set_layout,
            .vk_compute_descriptor_set = vk_compute_descriptor_set,
            .vk_mesh_descriptor_set_layout = vk_mesh_descriptor_set_layout,
            .vk_mesh_descriptor_set = vk_mesh_descriptor_set,
        };
    }

    pub fn destroy(self: *GlobalDescriptor, ctx: *GraphicsContext) void {
        ctx.device.destroyDescriptorSetLayout(self.vk_compute_descriptor_set_layout, null);
        ctx.device.destroyDescriptorSetLayout(self.vk_mesh_descriptor_set_layout, null);
    }
};

allocator: std.mem.Allocator,
stats: Stats,

ctx: *GraphicsContext,

uniforms: Uniforms = undefined,

// passes: struct {
//     clear: RenderPass = undefined,
//     solid: RenderPass = undefined,
// } = .{},
swapchain: Swapchain = undefined,
// framebuffer: Framebuffer = undefined,

// triangle_buffer: Buffer = undefined,
batcher_buffer: Buffer = undefined,
text_buffer: Buffer = undefined,
uniform_buffer: Buffer = undefined,

triangle_mesh: Mesh = undefined,
quad_mesh: Mesh = undefined,

// Global descriptors
descriptor: GlobalDescriptor = undefined,

// nearest_sampler: Sampler = undefined,
pipelines: std.EnumArray(PipelineType, Pipeline) = .initUndefined(),
images: std.EnumArray(ImageType, Image) = .initUndefined(),

// imgui_draw_data: *ig.ImDrawData = undefined,
imgui_draw_data: *anyopaque = undefined,

batcher: Batcher,
is_minimised: bool = false,

frame_number: u64 = 0,
frame_data: [FRAME_OVERLAP]FrameData = [2]FrameData{ .{}, .{} },

const triangle_vertices = [_]Data.Quad.Vertex{
    .{ .pos = .{ 0, -0.5 }, .uv = .{ 0.5, 0 }, .col = .{ 1, 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5 }, .uv = .{ 1, 1 }, .col = .{ 0, 1, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .uv = .{ 0, 1 }, .col = .{ 0, 0, 1, 1 } },
};
const quad_vertices = [_]Data.Quad.Vertex{
    .{ .pos = .{ 0.5, -0.5 }, .uv = .{ 1, 0 }, .col = .{ 1, 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5 }, .uv = .{ 1, 1 }, .col = .{ 0.5, 0.5, 0.5, 1 } },
    .{ .pos = .{ -0.5, -0.5 }, .uv = .{ 0, 0 }, .col = .{ 0, 0, 1, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .uv = .{ 0, 1 }, .col = .{ 0, 1, 0, 1 } },
};
const quad_indices = [_]Data.Quad.Indice{
    0, 1, 2,
    2, 1, 3,
};

pub fn init(allocator: std.mem.Allocator, ctx: *GraphicsContext) !Renderer {
    return .{
        .allocator = allocator,
        .stats = .init(),
        .batcher = try .init(allocator),
        .ctx = ctx,
    };
}

pub fn deinit(self: *Renderer) void {
    self.ctx.device.deviceWaitIdle() catch |err| {
        Logger.err("[Renderer2D.deinit] Error {}", .{err});
        unreachable;
    };

    for (&self.pipelines.values) |*pipeline| {
        pipeline.destroy(self.ctx);
    }

    for (&self.frame_data) |*fd| {
        fd.destroy(self.ctx);
    }

    for (&self.images.values) |*image| {
        image.destroy(self.ctx);
    }

    // self.nearest_sampler.destroy(self.ctx);

    self.descriptor.destroy(self.ctx);

    // self.triangle_buffer.destroy(self.ctx);
    self.triangle_mesh.destroy(self.ctx);
    self.quad_mesh.destroy(self.ctx);
    self.batcher_buffer.destroy(self.ctx);
    self.text_buffer.destroy(self.ctx);
    self.uniform_buffer.destroy(self.ctx);
    self.batcher.deinit();

    // self.framebuffer.destroy(self.ctx);

    // self.passes.clear.destroy(self.ctx);
    // self.passes.solid.destroy(self.ctx);
    self.swapchain.deinit();
}

pub fn setup(self: *Renderer) !void {
    self.initUniform();

    self.swapchain = try Swapchain.init(self.ctx, self.allocator);
    // self.passes.clear = try RenderPass.create(self.ctx, self.swapchain, .{});
    // self.passes.solid = try RenderPass.create(self.ctx, self.swapchain, .{ .load_op = .load, .store_op = .store });

    for (&self.frame_data) |*fd| {
        try fd.setup(self.ctx);
    }

    const draw_image = try Image.create(
        self.ctx,
        .{
            .transfer_src_bit = true,
            .transfer_dst_bit = true,
            .storage_bit = true,
            .color_attachment_bit = true,
        },
        .{ .device_local_bit = true },
        .{
            .width = @intCast(self.ctx.window.getWidth()),
            .height = @intCast(self.ctx.window.getHeight()),
            .depth = 1,
        },
        .r16g16b16a16_sfloat,
        // self.swapchain.surface_format.format,
    );
    self.images.set(.draw, draw_image);
    self.descriptor = try GlobalDescriptor.create(self.allocator, self.ctx);

    for (0..FRAME_OVERLAP) |i| {
        const frame_sizes = &[_]Descriptor.Allocator.PoolSizeRatio{
            .{ .vk_type = .storage_image, .ratio = 3 },
            .{ .vk_type = .storage_buffer, .ratio = 3 },
            .{ .vk_type = .uniform_buffer, .ratio = 3 },
            .{ .vk_type = .combined_image_sampler, .ratio = 4 },
        };
    }

    const surface = try Image.loadImageAsset("assets/images/Background.jpg", .array_rgba_32);
    const image = try Image.createFromSurface(self.ctx, surface, .{ .transfer_dst_bit = true, .sampled_bit = true }, .{ .device_local_bit = true });
    self.images.set(.atlas, image);
    // self.nearest_sampler = try .create(self.ctx, .nearest);

    // self.triangle_buffer = try Buffer.create(self.ctx, @sizeOf(@TypeOf(vertices)), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true }, .{ .device_local_bit = true });
    self.uniform_buffer = try Buffer.create(self.ctx, @sizeOf(@TypeOf(self.uniforms.transform)), .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    try self.uniform_buffer.copyInto(self.ctx, &std.mem.toBytes(self.uniforms.transform), 0);

    self.batcher_buffer = try Buffer.create(self.ctx, self.batcher.getTransferBufferSizeInBytes(), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .host_coherent_bit = true, .host_visible_bit = true });

    self.text_buffer = try Buffer.create(self.ctx, @intCast(self.images.get(.atlas).size), .{ .transfer_dst_bit = true }, .{ .device_local_bit = true });

    // const quad_mesh = try Mesh.makeQuadMesh(self.ctx, &self.cmd_pool, quad_vertices, indices: [6]u16)
    self.triangle_mesh = try Mesh.makeTriangleMesh(self.ctx, &self.getCurrentFrame().cmd_pool, triangle_vertices);

    // const quad_mesh = try Mesh.makeQuadMesh(self.ctx, &self.cmd_pool, quad_vertices, indices: [6]u16)
    self.quad_mesh = try Mesh.makeQuadMesh(self.ctx, &self.getCurrentFrame().cmd_pool, quad_vertices, &quad_indices);

    // Create Pipelines
    try self.createTrianglePipeline();
    // try self.create2DPipeline();
    try self.createMeshPipeline();
    try self.createComputePipeline();

    try self.text_buffer.fastTransfer(self.ctx, &self.getCurrentFrame().cmd_pool, surface.getPixels().?);
    // try self.triangle_buffer.fastTransfer(self.ctx, &self.cmd_pool, &std.mem.toBytes(vertices));
}

pub fn initUniform(self: *Renderer) void {
    // Setup the uniform buffers
    const width: usize = self.ctx.window.getWidth();
    const heigth: usize = self.ctx.window.getHeight();
    const fov: f32 = 40;
    const near: f32 = 0.0001;
    const far: f32 = 1000;

    self.uniforms = .{
        .transform = .{
            .scale = .{ 0.5, 0.5 },
            .translate = .{ 0, 0 },
        },
        .mvp = .{
            .proj_matrix = zm.perspectiveFovRh(zm.modAngle(fov), @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(heigth)), near, far),
            // .proj_matrix = zm.identity(),
            .view_matrix = zm.identity(),
        },
        .time = .{
            .time = 0,
        },
    };
}

pub fn getCurrentFrame(self: *Renderer) *FrameData {
    return &self.frame_data[self.frame_number % FRAME_OVERLAP];
}

fn fillCommandBuffers(self: *Renderer) !void {
    self.stats.startClock(.render_passes);
    defer self.stats.tickClock(.render_passes);

    try self.swapchain.waitForAllFences();

    const draw_image = self.images.getPtr(.draw);
    const current_frame = self.getCurrentFrame();
    const cmdbuf = current_frame.cmd_buf;

    const cmd_begin_info: vk.CommandBufferBeginInfo = .{ .flags = .{ .one_time_submit_bit = true } };
    try self.ctx.device.resetCommandBuffer(cmdbuf, .{});
    try self.ctx.device.beginCommandBuffer(cmdbuf, &cmd_begin_info);

    self.ctx.device.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&current_frame.viewport));
    self.ctx.device.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&current_frame.scissor));

    draw_image.transitionToLayout(self.ctx, cmdbuf, .undefined, .general);

    self.draw_background(cmdbuf);

    draw_image.transitionToLayout(self.ctx, cmdbuf, .general, .color_attachment_optimal);

    // self.draw_triangle(cmdbuf);
    self.draw_mesh(cmdbuf);

    draw_image.transitionToLayout(self.ctx, cmdbuf, .color_attachment_optimal, .transfer_src_optimal);
    Image.vkTransitionToLayout(self.swapchain.currentImage(), self.ctx, cmdbuf, .undefined, .transfer_dst_optimal);

    Image.vkCopyImageToImage(self.ctx, cmdbuf, draw_image.vk_image, self.swapchain.currentImage(), self.ctx.window.toExtend2D(), self.swapchain.extent);

    Image.vkTransitionToLayout(self.swapchain.currentImage(), self.ctx, cmdbuf, .transfer_dst_optimal, .color_attachment_optimal);

    Image.vkTransitionToLayout(self.swapchain.currentImage(), self.ctx, cmdbuf, .color_attachment_optimal, .present_src_khr);

    // { // 2D
    //     self.ctx.device.cmdBeginRenderPass(cmdbuf, &.{
    //         .render_pass = self.passes.solid.vk_render_pass,
    //         .framebuffer = framebuffer,
    //         .render_area = self.frame_data.scissor,
    //         .clear_value_count = 1,
    //         .p_clear_values = @ptrCast(&self.frame_data.clear_color),
    //     }, .@"inline");
    //     defer self.ctx.device.cmdEndRenderPass(cmdbuf);
    //
    //     self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, self.pipelines.get(._2d).vk_pipeline);
    //
    //     const offset = [_]vk.DeviceSize{0};
    //     self.ctx.device.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&self.triangle_mesh.buffers.vertex), &offset);
    //     self.ctx.device.cmdDraw(cmdbuf, vertices.len, 1, 0, 0);
    // }

    try self.ctx.device.endCommandBuffer(cmdbuf);
}

pub fn draw_triangle(self: *Renderer, cmdbuf: vk.CommandBuffer) void {
    const draw_image = self.images.getPtr(.draw);
    const current_frame = self.getCurrentFrame();

    self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, self.pipelines.get(.triangle).vk_pipeline);
    // const offset = [_]vk.DeviceSize{0};

    // self.ctx.device.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&self.triangle_mesh.buffers.vertex), &offset);

    const color_attachment: vk.RenderingAttachmentInfo = .{
        .image_layout = .color_attachment_optimal,
        .image_view = draw_image.view,
        .resolve_mode = .{},
        .resolve_image_layout = .color_attachment_optimal,
        .load_op = .load,
        .store_op = .store,
        .clear_value = .{
            .color = .{
                .float_32 = [_]f32{ 0, 0, 0, 0 }, // 0,0,0,0 transparent
            },
        },
    };

    const rendering_info: vk.RenderingInfo = .{
        .layer_count = 1,
        .render_area = current_frame.scissor,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&.{color_attachment}),
    };

    self.ctx.device.cmdBeginRendering(cmdbuf, &rendering_info);
    defer self.ctx.device.cmdEndRendering(cmdbuf);

    // self.ctx.device.cmdDraw(cmdbuf, vertices.len, 1, 0, 0);
    self.ctx.device.cmdDraw(cmdbuf, 3, 1, 0, 0);
}

pub fn draw_mesh(self: *Renderer, cmdbuf: vk.CommandBuffer) void {
    const draw_image = self.images.getPtr(.draw);
    const current_frame = self.getCurrentFrame();

    self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, self.pipelines.get(.mesh).vk_pipeline);
    // const offset = [_]vk.DeviceSize{0};

    // self.ctx.device.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&self.triangle_mesh.buffers.vertex), &offset);

    const color_attachment: vk.RenderingAttachmentInfo = .{
        .image_layout = .color_attachment_optimal,
        .image_view = draw_image.view,
        .resolve_mode = .{},
        .resolve_image_layout = .color_attachment_optimal,
        .load_op = .load,
        .store_op = .store,
        .clear_value = .{
            .color = .{
                .float_32 = [_]f32{ 0, 0, 0, 0 }, // 0,0,0,0 transparent
            },
        },
    };

    const rendering_info: vk.RenderingInfo = .{
        .layer_count = 1,
        .render_area = current_frame.scissor,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&.{color_attachment}),
    };

    const push_constant: Mesh.PushConstants2D = .{ .scale = .{ 1, 1 }, .translate = .{ 0, 0 }, .vb_address = self.quad_mesh.buffers.vertex.?.address.? };
    self.ctx.device.cmdPushConstants(cmdbuf, self.pipelines.getPtr(.mesh).layout, .{ .vertex_bit = true }, 0, @sizeOf(Mesh.PushConstants2D), @ptrCast(&push_constant));
    self.ctx.device.cmdBindIndexBuffer(cmdbuf, self.quad_mesh.buffers.index.?.vk_buffer, 0, .uint16);

    self.ctx.device.cmdBeginRendering(cmdbuf, &rendering_info);
    defer self.ctx.device.cmdEndRendering(cmdbuf);

    // Done in the triangle
    // self.ctx.device.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&current_frame.viewport));
    // self.ctx.device.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&current_frame.scissor));

    // self.ctx.device.cmdDraw(cmdbuf, quad_indices.len, 1, 0, 0);
    // self.ctx.device.cmdDraw(cmdbuf, 3, 1, 0, 0);
    // self.ctx.device.cmdDraw(cmdbuf, 4, 1, 0, 0);
    // self.ctx.device.cmdDrawIndexed(cmdbuf, 6, 1, 0, 0, 0);
    self.ctx.device.cmdDrawIndexed(cmdbuf, 6, 1, 0, 0, 0);
}

pub fn draw_background(self: *Renderer, cmdbuf: vk.CommandBuffer) void {
    // const draw_image = self.images.getPtr(.draw);
    // const current_frame = self.getCurrentFrame();

    self.ctx.device.cmdBindPipeline(cmdbuf, .compute, self.pipelines.get(.compute).vk_pipeline);
    self.ctx.device.cmdBindDescriptorSets(
        cmdbuf,
        .compute,
        self.pipelines.get(.compute).layout,
        0,
        1,
        @ptrCast(&self.descriptor.vk_compute_descriptor_set),
        0,
        null,
    );

    // Dispatch (16x16 workgroup size, so divide image size by 16)
    const group_count_x: u32 = @intCast((self.ctx.window.getWidth()) / 16); // Round up
    const group_count_y: u32 = @intCast((self.ctx.window.getHeight()) / 16); // Round up

    self.ctx.device.cmdDispatch(cmdbuf, group_count_x, group_count_y, 1);
}

pub fn flush(self: *Renderer, draw_queue: *Command.DrawQueue) void {
    Logger.debug("[Renderer2D.flush] {} Draw Commands", .{draw_queue.cmds.cur_pos});
    // draw_queue.sort() // optimise draw calls ?

    self.batcher.begin();

    for (draw_queue.cmds.buffer.items) |draw_cmd| {
        if (self.batcher.shouldFlush(draw_cmd)) {
            self.batcher.flush();
        }

        switch (draw_cmd) {
            .imgui => |cmd| self.imgui_draw_data = cmd.data,
            else => self.batcher.push(draw_cmd),
        }
    }

    const batches = self.batcher.end();

    // TODO, if can't draw all in 1 batch, process max cmd as possible using a pointer to count how many commands are left
    // For now, rewind to 0
    draw_queue.cmds.rewind(0);

    // TODO, remove panic?
    self.draw(batches) catch |err| @panic(@errorName(err));
}

pub fn draw(self: *Renderer, batches: []Batcher.Batch) !void {
    Logger.info("[Renderer2D.draw] Drawing {} batches", .{batches.len});
    var current_frame = self.getCurrentFrame();

    self.stats.startFrame();
    self.stats.startClock(.frame);
    defer {
        self.stats.tickClock(.frame);
        self.stats.endFrame();
        self.stats.samplePrint(5000); // print every 5000 frames
    }

    // Copy Pass just upload vertices + indexes
    // First pass: calculate total sizes
    var total_vertex_bytes: u32 = 0;
    var total_index_bytes: u32 = 0;
    var total_indices: u32 = 0;
    var total_vertices: u32 = 0;

    for (batches) |*batch| {
        assert(batch.cur_indices <= batch.indices.items.len); // Debug just in case
        total_vertex_bytes += @intCast(batch.vertices.sizeInBytes());
        total_index_bytes += @intCast(batch.getCurrentIndicesInBytes());
        total_indices += batch.cur_indices;
        total_vertices += @intCast(batch.vertices.cur_pos);
    }

    if (current_frame.shouldReset(self.ctx)) {
        self.swapchain.recreate(.{
            .width = @intCast(self.ctx.window.getWidth()),
            .height = @intCast(self.ctx.window.getHeight()),
        }) catch {
            current_frame.swapchain_state = .suboptimal;
            self.stats.addSkippedDraw();
            return;
        };
        current_frame.reset(self.ctx, self.swapchain.extent) catch {
            self.stats.addSkippedDraw();
            return;
        };
    }

    self.fillCommandBuffers() catch {
        current_frame.swapchain_state = .suboptimal;
        self.stats.addSkippedDraw();
        return;
    };

    current_frame.swapchain_state = self.swapchain.present(current_frame.cmd_buf) catch |err| blk: {
        self.stats.addSkippedDraw();
        std.debug.print("Present failed: {}\n", .{err});
        break :blk switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };
    };

    self.frame_number += 1;
}

fn createTrianglePipeline(self: *Renderer) !void {
    var elements = [_]Buffer.BufferElement{
        Buffer.BufferElement.new(.Float2, "Position"),
        Buffer.BufferElement.new(.Float2, "TexCoord"),
        Buffer.BufferElement.new(.Float4, "Color"),
    };
    const layout: Buffer.BufferLayout = .init(&elements);
    _ = layout;

    var vert = try Shader.create(self.ctx, .{ .name = "demo.spv", .stage = .vertex });
    defer vert.destroy(self.ctx);
    var frag = try Shader.create(self.ctx, .{ .name = "demo.spv", .stage = .fragment });
    defer frag.destroy(self.ctx);

    var pipeline_builder = try Pipeline.Builder.init(self.allocator);
    defer pipeline_builder.deinit();
    try pipeline_builder.setShaders(&vert, &frag);
    pipeline_builder.setColorAttachmentFormat(.r16g16b16a16_sfloat);

    pipeline_builder.pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    }, null);

    const pipeline = try pipeline_builder.buildPipeline(self.ctx);

    self.pipelines.set(.triangle, pipeline);
}

fn create2DPipeline(self: *Renderer) !void {
    // var elements = [_]Buffer.BufferElement{
    //     Buffer.BufferElement.new(.Float2, "Position"),
    //     Buffer.BufferElement.new(.Float2, "TexCoord"),
    //     Buffer.BufferElement.new(.Float4, "Color"),
    // };
    // const layout: Buffer.BufferLayout = .init(&elements);
    // _ = layout;

    var vert = try Shader.create(self.ctx, .{ .name = "2d.spv", .stage = .vertex });
    defer vert.destroy(self.ctx);
    var frag = try Shader.create(self.ctx, .{ .name = "2d.spv", .stage = .fragment });
    defer frag.destroy(self.ctx);

    var pipeline_builder = try Pipeline.Builder.init(self.allocator);
    defer pipeline_builder.deinit();
    try pipeline_builder.setShaders(&vert, &frag);
    pipeline_builder.setColorAttachmentFormat(.r16g16b16a16_sfloat);

    // var desc_builder = try Descriptor.LayoutBuilder.init(self.allocator);
    // defer desc_builder.deinit();
    // try desc_builder.addBinding(0, .storage_buffer);
    // const pipeline_layout = try desc_builder.build(self.ctx, .{ .vertex_bit = true }, .{}, null);
    pipeline_builder.pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    }, null);

    const pipeline = try pipeline_builder.buildPipeline(self.ctx);

    self.pipelines.set(._2d, pipeline);
}

fn createMeshPipeline(self: *Renderer) !void {
    // var elements = [_]Buffer.BufferElement{
    //     Buffer.BufferElement.new(.Float2, "Position"),
    //     Buffer.BufferElement.new(.Float2, "TexCoord"),
    //     Buffer.BufferElement.new(.Float4, "Color"),
    // };
    // const layout: Buffer.BufferLayout = .init(&elements);
    // _ = layout;

    var vert = try Shader.create(self.ctx, .{ .name = "mesh.spv", .stage = .vertex });
    defer vert.destroy(self.ctx);
    var frag = try Shader.create(self.ctx, .{ .name = "mesh.spv", .stage = .fragment });
    defer frag.destroy(self.ctx);

    var pipeline_builder = try Pipeline.Builder.init(self.allocator);
    defer pipeline_builder.deinit();
    try pipeline_builder.setShaders(&vert, &frag);
    pipeline_builder.setInputTopology(.triangle_list);
    pipeline_builder.setPolygonMode(.fill);
    pipeline_builder.setCullMode(.{}, .clockwise);
    pipeline_builder.setMultisamplingNone();
    pipeline_builder.disableBlending();
    pipeline_builder.disableDepthTest();
    pipeline_builder.setColorAttachmentFormat(self.images.getPtr(.draw).format);
    pipeline_builder.setDepthFormat(.undefined);

    const push_constant_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(Mesh.PushConstants2D), .stage_flags = .{ .vertex_bit = true } };

    pipeline_builder.pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    const pipeline = try pipeline_builder.buildPipeline(self.ctx);

    self.pipelines.set(.mesh, pipeline);
}

fn createComputePipeline(self: *Renderer) !void {
    // var compute = try Shader.create(self.ctx, .{ .name = "compute.spv", .stage = .compute });
    var compute = try Shader.create(self.ctx, .{ .name = "sky.spv", .stage = .compute });
    defer compute.destroy(self.ctx);

    // self.descriptor
    // const pipeline = try Pipeline.createComputePipeline(self.ctx, compute, try Pipeline.createPipelineLayout(self.ctx));

    const pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&self.descriptor.vk_compute_descriptor_set_layout),
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);

    const pipeline = try Pipeline.createComputePipeline(self.ctx, compute, pipeline_layout);

    self.pipelines.set(.compute, pipeline);
}
