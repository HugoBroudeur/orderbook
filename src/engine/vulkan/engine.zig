const std = @import("std");
const assert = std.debug.assert;
const sdl = @import("sdl3");
const vk = @import("vulkan");
const tracy = @import("tracy");

const zm = @import("zmath");

const materials = @import("../graphics/materials.zig");
const ComputeEffect = @import("../graphics/effects.zig").ComputeEffect;
const Skybox = @import("../graphics/skybox.zig");
const Scene = @import("../../scene_management/scene.zig");
const SceneGraph = @import("../../scene_management/graph.zig").SceneGraph;
const Objects = @import("../../scene_management/objects.zig");
const Node = Objects.Node;
const RenderObject = Objects.RenderObject;
const Buffers = @import("../graphics/buffers.zig");
const GPUDrawPushConstants = Buffers.GPUDrawPushConstants;
const Color = @import("../../primitive.zig").Color;
const Components = @import("../../ecs/components.zig");

// const Api = @import("../backend.zig").Vulkan;
// const Api = @import("../gfx.zig").Backend(.vulkan);
const ResourceManager = @import("../../resource_management/manager.zig").ResourceManager;
const Batcher = @import("batcher.zig");
const Buffer = @import("buffer.zig");
const Command = @import("../command.zig");
const Config = @import("../../config.zig");
const VulkanCommand = @import("command_pool.zig");
const Data = @import("../data.zig");
const DescriptorAllocator = @import("descriptor.zig").DescriptorAllocator;
const DescriptorWriter = @import("descriptor.zig").DescriptorWriter;
const DescriptorLayoutBuilder = @import("descriptor.zig").LayoutBuilder;
const DrawCommand = @import("../command.zig");
const Frame = @import("frames.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");
const ImageMetadata = @import("image.zig").ImageMetadata;
const AllocatedImage = @import("image.zig").AllocatedImage;
const Logger = @import("../../core/log.zig").MaxLogs(50);
const Pipeline = @import("pipeline.zig");
const RenderPass = @import("render_pass.zig");
const Sampler = @import("sampler.zig");
const SceneData = @import("../command.zig").SceneData;
const Shader = @import("shader.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const Bindless = @import("bindless.zig");
const BindlessRegistry = Bindless.Registry;

const Engine = @This();

pub const GPUCommandFn = fn (vk.CommandBuffer) anyerror!void;
pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const ImageType = enum { black, white, grey, error_checker };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { _2d };

pub const FRAME_OVERLAP = 2;

const SamplerCacheEntry = struct { option: Sampler.SamplerOption, sampler: Sampler };

io: std.Io,
allocator: std.mem.Allocator,
stats: *Components.Stats = undefined,

ctx: *const GraphicsContext,

swapchain: Swapchain = undefined,

batcher_buffer: Buffer = undefined,
// uniform_buffer: Buffer = undefined,

descriptor: BindlessRegistry = undefined,

draw_image: AllocatedImage = undefined,
depth_image: AllocatedImage = undefined,
pipelines: std.EnumArray(PipelineType, Pipeline) = .initUndefined(),
pipeline_layouts: std.EnumArray(PipelineType, vk.PipelineLayout) = .initUndefined(),
images: std.EnumArray(ImageType, AllocatedImage) = .initUndefined(),
samplers: std.EnumArray(SamplerType, Sampler) = .initUndefined(),

gui_render_fn: ?*const fn (vk.CommandBuffer) void = null,

batcher: Batcher,
pending_batches: []Batcher.Batch = &.{},
is_minimised: bool = false,
render_scale: f32 = 1.0,

frame_number: u64 = 0,

// Graphics
scene_graph: *SceneGraph = undefined,
// material_default_data: materials.MaterialInstance = undefined,
pbr_material: materials.PBRMaterial = .create(),

skybox_constants_buffer: Buffer = undefined,
skybox_texture: Skybox.CubemapTexture = .create(),

compute_effect: ComputeEffect = .create(),

// Draw optimisation
last_pipeline: ?*materials.MaterialPipeline = null,
last_material: ?*materials.MaterialInstance = null,
last_index_buffer: ?*Buffer = null,
// last_skybox: ?*Skybox.CubemapInstance = null,

// Sampler flyweight cache: a project uses under a dozen unique sampler
// option combos, so a linear scan beats hashing (SamplerOption has float
// fields that AutoHashMap rejects). Entries are destroyed in deinit only.
sampler_cache: std.ArrayList(SamplerCacheEntry) = .empty,

pub fn init(
    allocator: std.mem.Allocator,
    ctx: *const GraphicsContext,
    io: std.Io,
) !Engine {
    return .{
        .io = io,
        .allocator = allocator,
        .batcher = try .init(allocator),
        .ctx = ctx,
        // .draw_context = try .init(allocator),
    };
}

pub fn deinit(self: *Engine) void {
    self.ctx.device.deviceWaitIdle() catch |err| {
        Logger.err("[Engine.deinit] Error {}", .{err});
        unreachable;
    };

    // Destroy swapchain first (frames, command buffers, semaphores, fences)
    // before any other GPU resource cleanup.
    self.swapchain.deinit(self);

    for (&self.pipelines.values) |*pipeline| {
        pipeline.destroy(self.ctx);
    }
    for (&self.pipeline_layouts.values) |pipeline_layout| {
        self.ctx.device.destroyPipelineLayout(pipeline_layout, null);
    }

    self.descriptor.destroy(self);

    self.draw_image.destroy(self);
    self.depth_image.destroy(self);
    for (&self.images.values) |*image| {
        image.destroy(self);
    }

    for (&self.samplers.values) |*sampler| {
        sampler.destroy(self.ctx);
    }

    for (self.sampler_cache.items) |*entry| {
        entry.sampler.destroy(self.ctx);
    }
    self.sampler_cache.deinit(self.allocator);

    self.batcher_buffer.destroy();
    self.batcher.deinit();

    self.pbr_material.destroy(self);

    self.skybox_constants_buffer.destroy();
    self.skybox_texture.destroy(self);

    self.compute_effect.destroy(self);
    // self.draw_context.deinit();
}

pub fn setup(self: *Engine) !void {
    self.swapchain = try Swapchain.init(self, self.allocator);

    self.samplers.set(.nearest, try .create(self.ctx, .{}));
    self.samplers.set(.linear, try .create(self.ctx, .{ .min_filter = .linear, .mag_filter = .linear, .mipmap_mode = .linear, .max_lod = 1000 }));

    try self.createTextures();

    // self.descriptor = try GlobalDescriptor.create(self.allocator, self.ctx);
    self.descriptor = try BindlessRegistry.init(self);
    try self.descriptor.setupComputeImageSet(self.draw_image);
    try self.descriptor.setupGlobalSet();

    self.batcher_buffer = try Buffer.create(self, self.batcher.getTransferBufferSizeInBytes(), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .host_coherent_bit = true, .host_visible_bit = true });

    // Create Pipelines
    try self.create2DPipeline();
    try self.pbr_material.buildPipeline(self);
    try self.skybox_texture.buildPipeline(self);

    try self.compute_effect.buildPipeline(self);

    self.skybox_constants_buffer = try Skybox.CubemapTexture.createSkyboxPushConstantsBuffer(self, 1);
}

fn createTextures(self: *Engine) !void {
    { // Main Draw image
        self.draw_image = try AllocatedImage.create(self, self.ctx.window.getDimension(), .r16g16b16a16_sfloat, .{
            .transfer_src_bit = true,
            .transfer_dst_bit = true,
            .storage_bit = true,
            .color_attachment_bit = true,
        }, false, 1);
    }

    { // Main Depth image
        self.depth_image = try AllocatedImage.create(self, self.ctx.window.getDimension(), .d32_sfloat, .{
            .depth_stencil_attachment_bit = true,
        }, false, 1);
    }

    { // Some basic 1 or 2 pixel images
        const y = Color.Yellow.toBytes();
        const b = Color.Black.toBytes();
        const checker_bytes = y ++ b ++ b ++ y;

        var map: std.EnumMap(ImageType, []const u8) = .init(.{
            .white = &Color.White.toBytes(),
            .black = &Color.Black.toBytes(),
            .grey = &Color.Grey.toBytes(),
            .error_checker = &checker_bytes,
        });
        var it = map.iterator();
        while (it.next()) |m| {
            const size = std.math.sqrt(m.value.len / 4);
            var img = ImageMetadata.init(.{ .pixels = .{ .data = m.value.*, .format = .packed_rgba_8_8_8_8 } }, .{ .height = size, .width = size, .depth = 1 });

            const allocated_img = try AllocatedImage.create(self, .{ .width = size, .height = size, .depth = 1 }, .r8g8b8a8_unorm, .{ .sampled_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true }, false, 1);
            try img.upload(self, allocated_img);

            self.images.set(m.key, allocated_img);
        }
    }

    // { // Atlas
    //     const surface = try ImageMetadata.loadImageAssetWithFormat("assets/images/Background.jpg", .array_rgba_32);
    //     defer surface.deinit();
    //     const image = try ImageMetadata.createFromPath(
    //         self,
    //         "assets/images/Background.jpg",
    //         .array_rgba_32,
    //         .{ .sampled_bit = true },
    //     );
    //     self.images.set(.atlas, image);
    //     self.text_buffer = try Buffer.create(self.ctx, @intCast(self.images.get(.atlas).size), .{ .transfer_dst_bit = true }, .{ .device_local_bit = true });
    //     try self.text_buffer.fastTransfer(self.ctx, &self.getCurrentFrame().cmd_pool, surface.getPixels().?);
    // }
}

pub fn getCurrentFrame(self: *Engine) *Frame {
    return self.swapchain.getCurrentFrame();
}

pub fn render(self: *Engine, scene: *Scene, asset_pool: *ResourceManager) !void {
    _ = asset_pool;
    const camera = try scene.reg.app.getResource(Components.RenderCamera);
    const lights = try scene.reg.app.getResource(Components.Lights);
    const scene_data: SceneData = .{
        .view = camera.getViewMatrix(),
        .proj = camera.getProjectionMatrix(),
        .view_proj = camera.getViewProjMatrix(),
        .sunlight_color = lights.sunlight_color,
        .sunlight_direction = lights.sunlight_direction,
        .sunlight_specular_color = lights.sunlight_specular_color,
        .ambient_color = lights.ambient_color,
    };

    self.scene_graph = try scene.reg.app.getResource(Components.DrawContextQueue);

    self.stats = try scene.reg.app.getResource(Components.Stats);

    self.getCurrentFrame().scene_data = scene_data;

    // TODO
    // self.skybox_texture.load(self, asset_pool._images(skybox.));

    try self.draw();
}

fn draw(self: *Engine) !void {
    // // Skip if no work was prepared (minimised window etc.)
    // defer self.pending_batches = &.{};
    // Swapchain may be null after a failed recreate; skip the frame rather than
    // accessing self.frames which was freed by deinitExceptSwapchain.
    if (self.swapchain.handle == .null_handle) {
        return;
    }

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

    for (self.pending_batches) |*batch| {
        assert(batch.cur_indices <= batch.indices.items.len); // Debug just in case
        total_vertex_bytes += @intCast(batch.vertices.sizeInBytes());
        total_index_bytes += @intCast(batch.getCurrentIndicesInBytes());
        total_indices += batch.cur_indices;
        total_vertices += @intCast(batch.vertices.cur_pos);
    }

    const cur_window_size = self.ctx.window.toExtend2D();

    if (current_frame.swapchain_state == .suboptimal or self.swapchain.isRecreateNeeded(cur_window_size)) {
        self.swapchain.recreate(self, cur_window_size) catch {
            self.stats.addSkippedDraw();
            return;
        };

        self.resetCommandBuffers() catch {
            self.stats.addSkippedDraw();
            return;
        };

        // Re-fetch: recreate freed the old frames slice, old pointer is dangling.
        current_frame = self.getCurrentFrame();
    }

    const draw_extent: vk.Extent2D = .{
        .width = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.dimension.width))) * self.render_scale),
        .height = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.dimension.height))) * self.render_scale),
    };

    // self.draw_image.
    current_frame.resize(draw_extent);

    self.fillCommandBuffers() catch {
        current_frame.swapchain_state = .suboptimal;
        self.stats.addSkippedDraw();
        return;
    };

    // Present to Swapchain
    {
        self.stats.startClock(.present);

        current_frame.swapchain_state = self.swapchain.present(self) catch |err| blk: {
            self.stats.addSkippedDraw();
            break :blk switch (err) {
                error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
                else => |narrow| return narrow,
            };
        };

        self.stats.tickClock(.present);
    }

    self.frame_number += 1;
}

fn fillCommandBuffers(self: *Engine) !void {
    const current_frame = self.getCurrentFrame();

    // Fence wait
    {
        self.stats.startClock(.fence_wait);

        //wait until the gpu has finished rendering the last frame. Timeout of 1 second
        const result = try self.ctx.device.waitForFences(&.{current_frame.swap_image.frame_fence}, .true, 1_000_000_000);
        if (result != .success) {
            return error.waitForFences;
        }

        self.stats.tickClock(.fence_wait);
    }

    const cmd_buf = &current_frame.cmd_buf.vk_command_buffer;
    const swapchain_img = &self.swapchain.currentImage();
    try current_frame.frame_descriptor.clear(self.ctx);

    const cmd_begin_info: vk.CommandBufferBeginInfo = .{ .flags = .{ .one_time_submit_bit = true } };

    //now that we are sure that the commands finished executing, we can safely reset the command buffer to begin recording again.
    try self.ctx.device.resetCommandBuffer(cmd_buf.*, .{});
    try self.ctx.device.beginCommandBuffer(cmd_buf.*, &cmd_begin_info);

    // Compute background
    {
        self.stats.startClock(.compute_pass);

        self.draw_image.transitionLayout(self, current_frame.cmd_buf, .undefined, .general, 0, 1);
        self.drawEffects();

        self.stats.tickClock(.compute_pass);
    }

    // Bind data to GPU
    {
        self.stats.startClock(.transfer);

        try current_frame.scene_data_buffer.copyInto(&std.mem.toBytes(current_frame.scene_data), 0);
        current_frame.descriptor_set = try self.descriptor.writeFrameDescriptorSet(&current_frame.frame_descriptor, current_frame.scene_data_buffer);

        self.stats.tickClock(.transfer);
    }

    // Skybox
    {
        self.stats.startClock(.render_pass_3d);

        self.draw_image.transitionLayout(self, current_frame.cmd_buf, .general, .color_attachment_optimal, 0, 1);
        self.depth_image.transitionLayout(self, current_frame.cmd_buf, .undefined, .depth_attachment_optimal, 0, 1);
        // self.images.getPtr(.atlas).transitionToLayout(self, current_frame.cmd_buf, .undefined, .shader_read_only_optimal);
        try self.drawSkybox();

        // draw_image.transitionToLayout(self, current_frame.cmd_buf, .color_attachment_optimal, .transfer_src_optimal);

        // Image.vkTransitionToLayout(self, current_frame.cmd_buf, self.swapchain.currentImage(), .undefined, .transfer_dst_optimal, 0);
        // Image.copyImageToImage(self, current_frame.cmd_buf, draw_image.vk_image, self.swapchain.currentImage(), self.draw_extent, self.swapchain.extent);
        // Image.vkTransitionToLayout(self, current_frame.cmd_buf, self.swapchain.currentImage(), .transfer_dst_optimal, .color_attachment_optimal, 0);

        self.stats.tickClock(.render_pass_3d);
    }

    // Geometry
    {
        self.stats.startClock(.render_pass_3d);

        // draw_image.transitionToLayout(self, current_frame.cmd_buf, .general, .color_attachment_optimal);
        // depth_image.transitionToLayout(self, current_frame.cmd_buf, .undefined, .depth_attachment_optimal);
        // self.images.getPtr(.atlas).transitionToLayout(self, current_frame.cmd_buf, .undefined, .shader_read_only_optimal);
        try self.drawGeometry();

        self.draw_image.transitionLayout(self, current_frame.cmd_buf, .color_attachment_optimal, .transfer_src_optimal, 0, 1);

        swapchain_img.transitionLayout(self, current_frame.cmd_buf, .undefined, .transfer_dst_optimal, 0, 1);
        // ImageMetadata.vkTransitionToLayout(self, current_frame.cmd_buf, self.swapchain.currentImage(), .undefined, .transfer_dst_optimal, 0);
        self.draw_image.copyTo(self, current_frame.cmd_buf, self.swapchain.currentImage());
        swapchain_img.transitionLayout(self, current_frame.cmd_buf, .transfer_dst_optimal, .color_attachment_optimal, 0, 1);

        self.stats.tickClock(.render_pass_3d);
    }

    // Editor GUI
    {
        self.stats.startClock(.editor_pass);

        self.drawGuiEditor();

        self.stats.tickClock(.editor_pass);
    }

    // Transition blit to swapchain + close command buffer
    {
        self.stats.startClock(.blit);

        swapchain_img.transitionLayout(self, current_frame.cmd_buf, .color_attachment_optimal, .present_src_khr, 0, 1);
        try self.ctx.device.endCommandBuffer(cmd_buf.*);

        self.stats.tickClock(.blit);
    }
}

fn createCommandBuffers(self: *Engine, frame: *Frame) !void {
    try self.ctx.device.allocateCommandBuffers(&.{
        .command_pool = frame.cmd_pool.vk_cmd_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&frame.cmd_buf.vk_command_buffer));
}

fn resetCommandBuffers(self: *Engine) !void {
    var frame = self.getCurrentFrame();
    frame.swapchain_state = .optimal;

    self.ctx.device.freeCommandBuffers(frame.cmd_pool.vk_cmd_pool, &.{frame.cmd_buf.vk_command_buffer});
    try self.createCommandBuffers(frame);
}

// This pattern is not very efficient: we are waiting for the GPU command to fully execute before continuing with the CPU side logic.
// Recommended to run in seperate thread to load the data
pub fn immediateSubmit(self: *Engine, queue_family: GraphicsContext.QueueFamily, immediate_cmd: VulkanCommand.ImmediateCommands) !void {
    const begin_info = vk.CommandBufferBeginInfo{
        .flags = .{ .one_time_submit_bit = true },
        .p_inheritance_info = null,
    };

    { // Issue commands
        try self.ctx.device.beginCommandBuffer(immediate_cmd.buffer.vk_command_buffer, &begin_info);

        for (immediate_cmd.commands.items) |cmd| {
            try cmd.execute(self);
        }

        try self.ctx.device.endCommandBuffer(immediate_cmd.buffer.vk_command_buffer);
    }

    const submit_infos = [_]vk.SubmitInfo{.{
        .wait_semaphore_count = 0,
        .p_wait_semaphores = undefined,
        .p_wait_dst_stage_mask = undefined,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&immediate_cmd.buffer.vk_command_buffer),
        .signal_semaphore_count = 0,
        .p_signal_semaphores = undefined,
    }};

    const queue = queue_family.getQueue(self.ctx);
    try self.ctx.device.queueSubmit(queue, &submit_infos, .null_handle);
    try self.ctx.device.queueWaitIdle(queue);
}

fn drawSkybox(self: *Engine) !void {
    if (self.scene_graph.skybox) |so| {
        const current_frame = self.getCurrentFrame();

        const color_attachment: vk.RenderingAttachmentInfo = .{
            .image_layout = .color_attachment_optimal,
            .image_view = self.draw_image.view,
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

        const depth_attachment = vk.RenderingAttachmentInfo{
            .image_layout = .depth_attachment_optimal,
            .image_view = self.depth_image.view,
            .resolve_mode = .{},
            .resolve_image_layout = .depth_attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };

        const rendering_info: vk.RenderingInfo = .{
            .layer_count = 1,
            .render_area = current_frame.scissor,
            .view_mask = 0,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&.{color_attachment}),
            .p_depth_attachment = &depth_attachment,
        };

        self.ctx.device.cmdBeginRendering(self.getCurrentFrame().cmd_buf.vk_command_buffer, &rendering_info);
        defer self.ctx.device.cmdEndRendering(self.getCurrentFrame().cmd_buf.vk_command_buffer);

        const st = self.skybox_texture;

        const pipeline = st.opaque_pipeline;

        // rebind pipeline and descriptor if the skybox has changed
        // rebind index buffer
        // if (@intFromPtr(so.skybox) != @intFromPtr(self.last_skybox)) {
        //     self.last_skybox = so.skybox;
        self.stats.addMaterialBind();

        self.stats.addPipelineBind();

        self.ctx.device.cmdBindPipeline(current_frame.cmd_buf.vk_command_buffer, .graphics, pipeline.pipeline.vk_pipeline);
        self.ctx.device.cmdBindDescriptorSets(current_frame.cmd_buf.vk_command_buffer, .graphics, pipeline.pipeline_layout, 0, &.{current_frame.descriptor_set}, null);

        self.ctx.device.cmdSetViewport(current_frame.cmd_buf.vk_command_buffer, 0, &.{self.getCurrentFrame().viewport});
        self.ctx.device.cmdSetScissor(current_frame.cmd_buf.vk_command_buffer, 0, &.{self.getCurrentFrame().scissor});

        // self.ctx.device.cmdBindDescriptorSets(cmdbuf.vk_command_buffer, .graphics, pipeline.pipeline_layout, 1, &.{ro.material.material_set}, null);

        self.stats.addIndexBufferBind();
        self.ctx.device.cmdBindIndexBuffer(current_frame.cmd_buf.vk_command_buffer, so.index_buffer.vk_buffer, 0, .uint32);
        // }

        const push_constant: GPUDrawPushConstants = .{
            .render_matrix = so.transform,
            .vb_address = so.vertex_buffer.address.?,
            .material_buffer_slot = 0, //so.skybox.buffer_slot_idx,
            .material_index = 0, //so.material.material_idx,
        };

        self.ctx.device.cmdPushConstants(current_frame.cmd_buf.vk_command_buffer, pipeline.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(GPUDrawPushConstants), @ptrCast(&push_constant));
        self.ctx.device.cmdDrawIndexed(current_frame.cmd_buf.vk_command_buffer, so.index_count, 1, so.first_index, 0, 0);
        self.stats.addDrawCall(so.index_count / 3, so.index_count);
    }
}

fn drawGeometry(self: *Engine) !void {
    const current_frame = self.getCurrentFrame();

    self.stats.frame_transparent_objects = @intCast(self.scene_graph.transparent_surfaces.items.len);
    const color_attachment: vk.RenderingAttachmentInfo = .{
        .image_layout = .color_attachment_optimal,
        .image_view = self.draw_image.view,
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

    const depth_attachment = vk.RenderingAttachmentInfo{
        .image_layout = .depth_attachment_optimal,
        .image_view = self.depth_image.view,
        .resolve_mode = .{},
        .resolve_image_layout = .depth_attachment_optimal,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
    };

    const rendering_info: vk.RenderingInfo = .{
        .layer_count = 1,
        .render_area = current_frame.scissor,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&.{color_attachment}),
        .p_depth_attachment = &depth_attachment,
    };

    try self.scene_graph.frustumCulling(current_frame.scene_data.view_proj);
    self.scene_graph.sort();
    self.stats.frame_opaque_objects = @intCast(self.scene_graph._opaque_sufaces_sorted.items.len);

    self.last_pipeline = null;
    self.last_material = null;
    self.last_index_buffer = null;

    self.ctx.device.cmdBeginRendering(self.getCurrentFrame().cmd_buf.vk_command_buffer, &rendering_info);

    for (self.scene_graph._opaque_sufaces_sorted.items) |i| {
        self.drawRenderObject(self.getCurrentFrame().cmd_buf, &self.scene_graph.opaque_surfaces.items[i], current_frame.descriptor_set);
    }

    for (self.scene_graph.transparent_surfaces.items) |*render_object| {
        self.drawRenderObject(self.getCurrentFrame().cmd_buf, render_object, current_frame.descriptor_set);
    }

    self.ctx.device.cmdEndRendering(self.getCurrentFrame().cmd_buf.vk_command_buffer);
}

fn drawRenderObject(
    self: *Engine,
    cmdbuf: VulkanCommand.AllocatedCommandBuffer,
    ro: *RenderObject,
    frame_descriptor_set: vk.DescriptorSet,
) void {
    const pipeline = ro.material.pipeline;

    if (@intFromPtr(ro.material) != @intFromPtr(self.last_material)) {
        self.last_material = ro.material;
        self.stats.addMaterialBind();

        // rebind pipeline and descriptor if the material has changed
        if (@intFromPtr(ro.material.pipeline) != @intFromPtr(self.last_pipeline)) {
            self.last_pipeline = ro.material.pipeline;
            self.stats.addPipelineBind();

            self.ctx.device.cmdBindPipeline(cmdbuf.vk_command_buffer, .graphics, pipeline.pipeline.vk_pipeline);
            self.ctx.device.cmdBindDescriptorSets(cmdbuf.vk_command_buffer, .graphics, pipeline.pipeline_layout, 0, &.{frame_descriptor_set}, null);

            self.ctx.device.cmdSetViewport(cmdbuf.vk_command_buffer, 0, &.{self.getCurrentFrame().viewport});
            self.ctx.device.cmdSetScissor(cmdbuf.vk_command_buffer, 0, &.{self.getCurrentFrame().scissor});
        }

        // self.ctx.device.cmdBindDescriptorSets(cmdbuf.vk_command_buffer, .graphics, pipeline.pipeline_layout, 1, &.{ro.material.material_set}, null);
    }

    // rebind index buffer if needed
    if (@intFromPtr(&ro.index_buffer) != @intFromPtr(self.last_index_buffer)) {
        self.last_index_buffer = &ro.index_buffer;
        self.stats.addIndexBufferBind();
        self.ctx.device.cmdBindIndexBuffer(cmdbuf.vk_command_buffer, ro.index_buffer.vk_buffer, 0, .uint32);
    }
    const push_constant: GPUDrawPushConstants = .{
        .render_matrix = ro.transform,
        .vb_address = ro.vertex_buffer.address.?,
        .material_buffer_slot = ro.material.buffer_slot_idx,
        .material_index = ro.material.material_idx,
    };

    self.ctx.device.cmdPushConstants(cmdbuf.vk_command_buffer, pipeline.pipeline_layout, .{ .vertex_bit = true, .fragment_bit = true }, 0, @sizeOf(GPUDrawPushConstants), @ptrCast(&push_constant));
    self.ctx.device.cmdDrawIndexed(cmdbuf.vk_command_buffer, ro.index_count, 1, ro.first_index, 0, 0);
    self.stats.addDrawCall(ro.index_count / 3, ro.index_count);
}

fn drawEffects(self: *Engine) void {
    self.ctx.device.cmdBindPipeline(self.getCurrentFrame().cmd_buf.vk_command_buffer, .compute, self.compute_effect.effect_pipeline.pipeline.vk_pipeline);
    self.ctx.device.cmdBindDescriptorSets(
        self.getCurrentFrame().cmd_buf.vk_command_buffer,
        .compute,
        self.compute_effect.effect_pipeline.pipeline_layout,
        0,
        &.{self.descriptor.draw_image_descriptor},
        null,
    );

    const group_count_x: u32 = (@max(self.getCurrentFrame().swap_image.image.dimension.width, 1) + 15) / 16;
    const group_count_y: u32 = (@max(self.getCurrentFrame().swap_image.image.dimension.height, 1) + 15) / 16;

    self.ctx.device.cmdDispatch(self.getCurrentFrame().cmd_buf.vk_command_buffer, group_count_x, group_count_y, 1);
}

fn drawGuiEditor(self: *Engine) void {
    if (self.gui_render_fn) |render_fn| {
        const color_attachment = vk.RenderingAttachmentInfo{
            .clear_value = .{
                .color = .{
                    .float_32 = [_]f32{ 0, 0, 0, 0 }, // 0,0,0,0 transparent
                },
            },
            .image_view = self.getCurrentFrame().swap_image.image.view,
            .image_layout = .color_attachment_optimal,
            .load_op = .load, // preserve blitted 3D content
            .store_op = .store,
            .resolve_mode = .{},
            .resolve_image_view = .null_handle,
            .resolve_image_layout = .undefined,
        };
        const rendering_info = vk.RenderingInfo{
            .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swapchain.extent },
            .layer_count = 1,
            .view_mask = 0,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&color_attachment),
            .p_depth_attachment = null,
            .p_stencil_attachment = null,
        };
        self.ctx.device.cmdBeginRendering(self.getCurrentFrame().cmd_buf.vk_command_buffer, &rendering_info);
        render_fn(self.getCurrentFrame().cmd_buf.vk_command_buffer);
        self.ctx.device.cmdEndRendering(self.getCurrentFrame().cmd_buf.vk_command_buffer);
    }
}

fn create2DPipeline(self: *Engine) !void {
    var vert = try Shader.create(self, .{ .name = "2d_bis.spv", .stage = .vertex });
    defer vert.destroy(self.ctx);
    var frag = try Shader.create(self, .{ .name = "2d_bis.spv", .stage = .fragment });
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
    pipeline_builder.setColorAttachmentFormat(self.draw_image.format);
    pipeline_builder.setDepthFormat(.undefined);

    const push_constant_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(GPUDrawPushConstants), .stage_flags = .{ .vertex_bit = true } };

    const set_layouts = [_]vk.DescriptorSetLayout{
        self.descriptor.vk_global_descriptor_set_layout, // set 0
        // self.descriptor.vk_material_descriptor_set_layout, // set 1
    };

    const pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .set_layout_count = set_layouts.len,
        .p_set_layouts = @ptrCast(&set_layouts),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    pipeline_builder.pipeline_layout = pipeline_layout;
    const pipeline = try pipeline_builder.buildPipeline(self.ctx);

    self.pipelines.set(._2d, pipeline);
    self.pipeline_layouts.set(._2d, pipeline_layout);
}

pub fn getSampler(self: *Engine, option: Sampler.SamplerOption) !Sampler {
    for (self.sampler_cache.items) |entry| {
        if (std.meta.eql(entry.option, option)) return entry.sampler;
    }

    const sampler = try Sampler.create(self.ctx, option);
    try self.sampler_cache.append(self.allocator, .{ .option = option, .sampler = sampler });
    return sampler;
}
