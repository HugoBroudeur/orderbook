const std = @import("std");
const assert = std.debug.assert;
const sdl = @import("sdl3");
const vk = @import("vulkan");
const tracy = @import("tracy");

const zm = @import("zmath");

const UiManager = @import("../../game/ui_manager.zig");
const EcsManager = @import("../../game/ecs_manager.zig");
const materials = @import("../graphics/materials.zig");
const ComputeEffect = @import("../graphics/effects.zig").ComputeEffect;
const Scene = @import("../graphics/scene.zig");
const DrawContext = Scene.DrawContext;
const IRenderable = Scene.IRenderable;
const MeshNode = Scene.MeshNode;
const LoadedGLTF = Scene.LoadedGLTF;
const Buffers = @import("../graphics/buffers.zig");
const RenderObject = @import("../graphics/objects.zig").RenderObject;
const Vertex = Buffers.Vertex;
const GPUDrawPushConstants = Buffers.GPUDrawPushConstants;
const GPUDrawPushConstants2D = Buffers.GPUDrawPushConstants2D;
const Color = @import("../../primitive.zig").Color;

// const Api = @import("../backend.zig").Vulkan;
// const Api = @import("../gfx.zig").Backend(.vulkan);
const AssetManager = @import("../asset_manager.zig");
const Batcher = @import("batcher.zig");
const Buffer = @import("buffer.zig");
const Camera = @import("../camera.zig");
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
const Image = @import("image.zig");
const Logger = @import("../../core/log.zig").MaxLogs(50);
const Mesh = @import("mesh.zig");
const Pipeline = @import("pipeline.zig");
const RenderPass = @import("render_pass.zig");
const Sampler = @import("sampler.zig");
const SceneData = @import("../command.zig").SceneData;
const SceneManager = @import("../scene_manager.zig");
const Shader = @import("shader.zig");
const Stats = @import("../stats.zig");
const Swapchain = @import("swapchain.zig").Swapchain;

const Engine = @This();

pub const GPUCommandFn = fn (vk.CommandBuffer) anyerror!void;
pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const ImageType = enum { atlas, black, white, grey, error_checker };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { _2d };

pub const FRAME_OVERLAP = 2;

const GlobalDescriptor = struct {

    // Create a descriptor pool that will hold 10 sets with 1 image each
    const MAX_SETS = 10;

    allocator: std.mem.Allocator,
    desc_allocator: DescriptorAllocator,
    writer: DescriptorWriter,
    is_initialised: bool = false,

    // Used in the Compute Shader
    draw_image_descriptor: vk.DescriptorSet = undefined,
    draw_image_descriptor_layout: vk.DescriptorSetLayout = undefined,

    // Global Scene
    vk_global_descriptor_set: vk.DescriptorSet = undefined,
    vk_global_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

    // Used in the 2D Shader
    vk_2d_descriptor_set: vk.DescriptorSet = undefined,
    vk_2d_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

    pub fn init(allocator: std.mem.Allocator, ctx: *const GraphicsContext) !GlobalDescriptor {
        var ratio = [_]DescriptorAllocator.PoolSizeRatio{
            .{ .vk_type = .storage_image, .ratio = 3 },
            .{ .vk_type = .uniform_buffer, .ratio = 4 },
            // .{ .vk_type = .sampled_image, .ratio = 1 },
            .{ .vk_type = .combined_image_sampler, .ratio = 4096 },
            // .{ .vk_type = .sampler, .ratio = 1 },
        };
        return .{
            .allocator = allocator,
            .desc_allocator = try DescriptorAllocator.init(allocator, ctx, MAX_SETS, &ratio),
            .writer = try .init(allocator),
        };
    }

    pub fn destroy(self: *GlobalDescriptor, ctx: *const GraphicsContext) void {
        self.desc_allocator.destroy(ctx);
        if (self.is_initialised) {
            ctx.device.destroyDescriptorSetLayout(self.draw_image_descriptor_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.vk_global_descriptor_set_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.vk_2d_descriptor_set_layout, null);
        }
        self.writer.deinit();
    }
};

io: std.Io,
allocator: std.mem.Allocator,
stats: Stats,

ctx: *const GraphicsContext,

swapchain: Swapchain = undefined,

batcher_buffer: Buffer = undefined,
text_buffer: Buffer = undefined,
// uniform_buffer: Buffer = undefined,

meshes: std.ArrayList(Mesh),

// Global descriptors
descriptor: GlobalDescriptor = undefined,

asset_loader: AssetManager,
draw_image: Image = undefined,
depth_image: Image = undefined,
pipelines: std.EnumArray(PipelineType, Pipeline) = .initUndefined(),
pipeline_layouts: std.EnumArray(PipelineType, vk.PipelineLayout) = .initUndefined(),
images: std.EnumArray(ImageType, Image) = .initUndefined(),
samplers: std.EnumArray(SamplerType, Sampler) = .initUndefined(),

// imgui_draw_data: *ig.ImDrawData = undefined,
imgui_draw_data: *anyopaque = undefined,
gui_render_fn: ?*const fn (vk.CommandBuffer) void = null,

batcher: Batcher,
pending_batches: []Batcher.Batch = &.{},
is_minimised: bool = false,
draw_extent: vk.Extent2D,
render_scale: f32 = 1.0,

frame_number: u64 = 0,

// Graphics
scene_manager: SceneManager = undefined,
draw_queue: Command.DrawQueue = undefined,
loaded_scenes: std.array_hash_map.String(LoadedGLTF),
draw_context: DrawContext,
loaded_nodes: std.StringHashMap(IRenderable),
// material_default_data: materials.MaterialInstance = undefined,
material_constants_buffer: Buffer = undefined,
metal_rough_material: materials.MetallicRoughness = .create(),

compute_effect: ComputeEffect = .create(),

// Draw optimisation
last_pipeline: ?*materials.MaterialPipeline = null,
last_material: ?*materials.MaterialInstance = null,
last_index_buffer: ?*Buffer = null,

// Bindless texture registry (slot 0 = grey fallback, seeded in setupDescriptors)
bindless_texture_count: u32 = 0,
texture_cache: std.ArrayList(vk.DescriptorImageInfo),

pub fn init(allocator: std.mem.Allocator, ctx: *const GraphicsContext, io: std.Io) !Engine {
    return .{
        .io = io,
        .allocator = allocator,
        .stats = .init(),
        .batcher = try .init(allocator),
        .ctx = ctx,
        .asset_loader = try .init(allocator, io),
        .draw_context = try .init(allocator),
        .meshes = try .initCapacity(allocator, 0),
        .loaded_nodes = .init(allocator),
        .loaded_scenes = .empty,
        .draw_extent = ctx.window.toExtend2D(),
        .texture_cache = .empty,
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

    self.descriptor.destroy(self.ctx);

    self.draw_image.destroy(self.ctx);
    self.depth_image.destroy(self.ctx);
    for (&self.images.values) |*image| {
        image.destroy(self.ctx);
    }

    for (&self.samplers.values) |*sampler| {
        sampler.destroy(self.ctx);
    }
    for (self.meshes.items) |*mesh| {
        mesh.destroy(self.ctx);
    }
    self.meshes.deinit(self.allocator);

    self.asset_loader.deinit(self);
    var scene_it = self.loaded_scenes.iterator();
    while (scene_it.next()) |scene_ptr| {
        scene_ptr.value_ptr.*.deinit();
    }
    self.loaded_scenes.deinit(self.allocator);

    self.batcher_buffer.destroy(self.ctx);
    self.text_buffer.destroy(self.ctx);
    self.material_constants_buffer.destroy(self.ctx);
    self.batcher.deinit();

    self.metal_rough_material.destroy(self);
    self.compute_effect.destroy(self);
    self.loaded_nodes.deinit();
    self.draw_context.deinit();
    self.texture_cache.deinit(self.allocator);
    self.scene_manager.deinit();
    self.draw_queue.deinit();
}

pub fn setup(self: *Engine) !void {
    self.swapchain = try Swapchain.init(self, self.allocator);

    self.samplers.set(.nearest, try .create(self.ctx, .{}));
    self.samplers.set(.linear, try .create(self.ctx, .{ .min_filter = .linear, .mag_filter = .linear, .mipmap_mode = .linear }));

    self.draw_queue = try Command.DrawQueue.init(self.allocator, self);
    self.scene_manager = SceneManager.init(&self.draw_queue, self.io);

    try self.createTextures();

    // self.descriptor = try GlobalDescriptor.create(self.allocator, self.ctx);
    self.descriptor = try GlobalDescriptor.init(self.allocator, self.ctx);
    try self.setupDescriptors();

    self.batcher_buffer = try Buffer.create(self.ctx, self.batcher.getTransferBufferSizeInBytes(), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .host_coherent_bit = true, .host_visible_bit = true });

    // Create Pipelines
    try self.create2DPipeline();
    try self.metal_rough_material.buildPipeline(self);

    try self.compute_effect.buildPipeline(self);

    self.material_constants_buffer = try materials.MetallicRoughness.createMaterialPushConstantsBuffer(self, 1);

    {
        self.stats.startClock(.transfer);
        // self.meshes = try self.asset_loader.loadMeshes(self, "assets/meshes/basic.glb");
        // self.meshes = try self.asset_loader.loadMeshes(self.ctx, &self.getCurrentFrame().cmd_pool, "assets/meshes/city.glb");
        const structure_file = try self.asset_loader.loadGLTFAsset(self, "assets/meshes/structure.glb");
        try self.loaded_scenes.put(self.allocator, "structure", structure_file);

        self.stats.tickClock(.transfer);
    }
}

pub fn createTextures(self: *Engine) !void {
    { // Main Draw image
        self.draw_image = try Image.create(
            self,
            .{
                .width = self.draw_extent.width,
                .height = self.draw_extent.height,
                .depth = 1,
            },
            .r16g16b16a16_sfloat,
            .{
                .transfer_src_bit = true,
                .transfer_dst_bit = true,
                .storage_bit = true,
                .color_attachment_bit = true,
            },
            true,
        );
    }

    { // Main Depth image
        self.depth_image = try Image.create(
            self,
            .{
                .width = self.draw_extent.width,
                .height = self.draw_extent.height,
                .depth = 1,
            },
            .d32_sfloat,
            .{
                .depth_stencil_attachment_bit = true,
            },
            false,
        );
    }

    { // Single 1px color
        var map: std.EnumMap(ImageType, ?Color) = .init(.{
            .white = .White,
            .black = .Black,
            .grey = .Grey,
        });
        var it = map.iterator();
        while (it.next()) |m| {
            if (m.value.*) |color|
                self.images.set(m.key, try Image.createFromColor(
                    self,
                    color,
                    .{ .height = 1, .width = 1, .depth = 1 },
                    .r8g8b8a8_unorm,
                    .{ .sampled_bit = true },
                ));
        }
    }

    { // Checker pattern
        const m = Color.Magenta.toBytes();
        const b = Color.Black.toBytes();
        const checker_bytes = m ++ b ++ b ++ m;

        self.images.set(.error_checker, try Image.createFromBytes(
            self,
            &checker_bytes,
            .{ .height = 2, .width = 2, .depth = 1 },
            .r8g8b8a8_unorm,
            .{ .sampled_bit = true },
            false,
        ));
    }

    { // Atlas
        const surface = try Image.loadImageAsset("assets/images/Background.jpg", .array_rgba_32);
        defer surface.deinit();
        const image = try Image.createFromPath(
            self,
            "assets/images/Background.jpg",
            .array_rgba_32,
            .{ .sampled_bit = true },
        );
        self.images.set(.atlas, image);
        self.text_buffer = try Buffer.create(self.ctx, @intCast(self.images.get(.atlas).size), .{ .transfer_dst_bit = true }, .{ .device_local_bit = true });
        try self.text_buffer.fastTransfer(self.ctx, &self.getCurrentFrame().cmd_pool, surface.getPixels().?);
    }
}

pub fn setupDescriptors(self: *Engine) !void {
    { // Compute image
        var builder: DescriptorLayoutBuilder = try .init(self.allocator);
        defer builder.deinit();

        try builder.addBinding(0, .storage_image);

        self.descriptor.draw_image_descriptor_layout = try builder.build(self.ctx, .{ .compute_bit = true }, .{}, null);
        self.descriptor.draw_image_descriptor = try self.descriptor.desc_allocator.allocate(self.ctx, self.descriptor.draw_image_descriptor_layout, null);

        self.descriptor.writer.clear();
        try self.descriptor.writer.writeImage(0, self.draw_image, self.samplers.get(.linear), .general, .storage_image);
        self.descriptor.writer.updateSet(self.ctx, self.descriptor.draw_image_descriptor);
    }
    { // Scene
        var builder = try DescriptorLayoutBuilder.init(self.allocator);
        defer builder.deinit();
        try builder.addBinding(0, .uniform_buffer);
        try builder.addBinding(1, .combined_image_sampler);
        builder.bindings.items[1].descriptor_count = 4048;

        const flags: [2]vk.DescriptorBindingFlags = .{
            .{},
            .{ .partially_bound_bit = true, .variable_descriptor_count_bit = true },
        };
        const bind_flags: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
            .binding_count = flags.len,
            .p_binding_flags = @ptrCast(&flags),
        };

        self.descriptor.vk_global_descriptor_set_layout = try builder.build(
            self.ctx,
            .{ .vertex_bit = true, .fragment_bit = true },
            .{},
            &bind_flags,
        );

        const variable_count: u32 = 4048;
        const variable_count_info: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{
            .descriptor_set_count = 1,
            .p_descriptor_counts = @ptrCast(&variable_count),
        };
        self.descriptor.vk_global_descriptor_set = try self.descriptor.desc_allocator.allocate(
            self.ctx,
            self.descriptor.vk_global_descriptor_set_layout,
            @ptrCast(&variable_count_info),
        );

        _ = try self.registerTexture(self.images.get(.white), self.samplers.get(.nearest));
    }
    { // 2D images (atlas)
        var builder = try DescriptorLayoutBuilder.init(self.allocator);
        defer builder.deinit();
        try builder.addBinding(0, .combined_image_sampler);
        try builder.addBinding(1, .combined_image_sampler);
        self.descriptor.vk_2d_descriptor_set_layout = try builder.build(self.ctx, .{ .fragment_bit = true }, .{}, null);
        self.descriptor.vk_2d_descriptor_set = try self.descriptor.desc_allocator.allocate(self.ctx, self.descriptor.vk_2d_descriptor_set_layout, null);

        self.descriptor.writer.clear();
        try self.descriptor.writer.writeImage(0, self.images.get(.atlas), self.samplers.get(.linear), .shader_read_only_optimal, .combined_image_sampler);
        self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_2d_descriptor_set);

        self.descriptor.writer.clear();
        try self.descriptor.writer.writeImage(1, self.images.get(.error_checker), self.samplers.get(.nearest), .shader_read_only_optimal, .combined_image_sampler);
        self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_2d_descriptor_set);
    }
    self.descriptor.is_initialised = true;
}

pub fn getCurrentFrame(self: *Engine) *Frame {
    return self.swapchain.getCurrentFrame();
}

pub fn draw(self: *Engine) !void {
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

    self.draw_extent = .{
        .width = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.dimension.width))) * self.render_scale),
        .height = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.dimension.height))) * self.render_scale),
    };
    current_frame.resize(self.draw_extent);

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

    const draw_image = &self.draw_image;
    const depth_image = &self.depth_image;
    const cmdbuf = &current_frame.cmd_buf.vk_command_buffer;
    try current_frame.frame_descriptor.clear(self.ctx);

    const cmd_begin_info: vk.CommandBufferBeginInfo = .{ .flags = .{ .one_time_submit_bit = true } };

    //now that we are sure that the commands finished executing, we can safely reset the command buffer to begin recording again.
    try self.ctx.device.resetCommandBuffer(cmdbuf.*, .{});
    try self.ctx.device.beginCommandBuffer(cmdbuf.*, &cmd_begin_info);

    // Compute background
    {
        self.stats.startClock(.compute_pass);

        draw_image.transitionToLayout(self, current_frame.cmd_buf, .undefined, .general);
        self.drawEffects();

        self.stats.tickClock(.compute_pass);
    }

    // Geometry
    {
        self.stats.startClock(.render_pass_3d);

        draw_image.transitionToLayout(self, current_frame.cmd_buf, .general, .color_attachment_optimal);
        depth_image.transitionToLayout(self, current_frame.cmd_buf, .undefined, .depth_attachment_optimal);
        self.images.getPtr(.atlas).transitionToLayout(self, current_frame.cmd_buf, .undefined, .shader_read_only_optimal);
        try self.drawGeometry();

        draw_image.transitionToLayout(self, current_frame.cmd_buf, .color_attachment_optimal, .transfer_src_optimal);

        Image.vkTransitionToLayout(self, current_frame.cmd_buf, self.swapchain.currentImage(), .undefined, .transfer_dst_optimal, 0);
        Image.copyImageToImage(self, current_frame.cmd_buf, draw_image.vk_image, self.swapchain.currentImage(), self.draw_extent, self.swapchain.extent);
        Image.vkTransitionToLayout(self, current_frame.cmd_buf, self.swapchain.currentImage(), .transfer_dst_optimal, .color_attachment_optimal, 0);

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

        Image.vkTransitionToLayout(self, current_frame.cmd_buf, self.swapchain.currentImage(), .color_attachment_optimal, .present_src_khr, 0);
        try self.ctx.device.endCommandBuffer(cmdbuf.*);

        self.stats.tickClock(.blit);
    }

    // Clear queues
    {
        self.draw_context.opaque_surfaces.clearRetainingCapacity();
        self.draw_context.transparent_surfaces.clearRetainingCapacity();
    }
}

pub fn createCommandBuffers(self: *Engine, frame: *Frame) !void {
    try self.ctx.device.allocateCommandBuffers(&.{
        .command_pool = frame.cmd_pool.vk_cmd_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&frame.cmd_buf.vk_command_buffer));
}

pub fn resetCommandBuffers(self: *Engine) !void {
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

pub fn drawGeometry(self: *Engine) !void {
    const current_frame = self.getCurrentFrame();

    // Populate draw context from the scene graph each frame
    {
        self.stats.startClock(.scene_build);

        var identity = zm.identity();

        try self.loaded_scenes.getPtr("structure").?.draw(&identity, &self.draw_context);

        self.stats.tickClock(.scene_build);
    }

    self.stats.frame_transparent_objects = @intCast(self.draw_context.transparent_surfaces.items.len);

    try current_frame.scene_data_buffer.copyInto(self.ctx, &std.mem.toBytes(current_frame.scene_data), 0);

    const variable_count: u32 = @intCast(self.texture_cache.items.len);
    const count_info: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{
        .descriptor_set_count = 1,
        .p_descriptor_counts = @ptrCast(&variable_count),
    };
    const frame_descriptor_set = try current_frame.frame_descriptor.allocate(
        self.ctx,
        self.descriptor.vk_global_descriptor_set_layout,
        @ptrCast(&count_info),
    );

    self.descriptor.writer.clear();
    try self.descriptor.writer.writeBuffer(0, current_frame.scene_data_buffer, current_frame.scene_data_buffer.size, 0, .uniform_buffer);

    if (self.texture_cache.items.len > 0) {
        const write = vk.WriteDescriptorSet{
            .dst_binding = 1,
            .dst_set = .null_handle, // filled by updateSet
            .dst_array_element = 0,
            .descriptor_count = @intCast(self.texture_cache.items.len),
            .descriptor_type = .combined_image_sampler,
            .p_image_info = self.texture_cache.items.ptr,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        try self.descriptor.writer.writes.append(self.descriptor.writer.allocator, write);
    }

    self.descriptor.writer.updateSet(self.ctx, frame_descriptor_set);

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

    try self.draw_context.frustumCulling(current_frame.scene_data.view_proj);
    self.draw_context.sort();
    self.stats.frame_opaque_objects = @intCast(self.draw_context._opaque_sufaces_sorted.items.len);

    self.last_pipeline = null;
    self.last_material = null;
    self.last_index_buffer = null;

    self.ctx.device.cmdBeginRendering(self.getCurrentFrame().cmd_buf.vk_command_buffer, &rendering_info);

    for (self.draw_context._opaque_sufaces_sorted.items) |i| {
        self.drawRenderObject(self.getCurrentFrame().cmd_buf, &self.draw_context.opaque_surfaces.items[i], frame_descriptor_set);
    }

    for (self.draw_context.transparent_surfaces.items) |*render_object| {
        self.drawRenderObject(self.getCurrentFrame().cmd_buf, render_object, frame_descriptor_set);
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

        self.ctx.device.cmdBindDescriptorSets(cmdbuf.vk_command_buffer, .graphics, pipeline.pipeline_layout, 1, &.{ro.material.material_set}, null);
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
    };

    self.ctx.device.cmdPushConstants(cmdbuf.vk_command_buffer, pipeline.pipeline_layout, .{ .vertex_bit = true }, 0, @sizeOf(GPUDrawPushConstants), @ptrCast(&push_constant));
    self.ctx.device.cmdDrawIndexed(cmdbuf.vk_command_buffer, ro.index_count, 1, ro.first_index, 0, 0);
    self.stats.addDrawCall(ro.index_count / 3, ro.index_count);
}

pub fn drawEffects(self: *Engine) void {
    self.ctx.device.cmdBindPipeline(self.getCurrentFrame().cmd_buf.vk_command_buffer, .compute, self.compute_effect.effect_pipeline.pipeline.vk_pipeline);
    self.ctx.device.cmdBindDescriptorSets(
        self.getCurrentFrame().cmd_buf.vk_command_buffer,
        .compute,
        self.compute_effect.effect_pipeline.pipeline_layout,
        0,
        &.{self.descriptor.draw_image_descriptor},
        null,
    );

    const group_count_x: u32 = (@max(self.draw_extent.width, 1) + 15) / 16;
    const group_count_y: u32 = (@max(self.draw_extent.height, 1) + 15) / 16;

    self.ctx.device.cmdDispatch(self.getCurrentFrame().cmd_buf.vk_command_buffer, group_count_x, group_count_y, 1);
}

pub fn drawGuiEditor(self: *Engine) void {
    if (self.gui_render_fn) |render_fn| {
        const color_attachment = vk.RenderingAttachmentInfo{
            .clear_value = .{
                .color = .{
                    .float_32 = [_]f32{ 0, 0, 0, 0 }, // 0,0,0,0 transparent
                },
            },
            .image_view = self.getCurrentFrame().swap_image.view,
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

pub fn updateScene(self: *Engine, draw_queue: *Command.DrawQueue) void {
    // Logger.debug("[Engine.update_scene] {} Draw Commands", .{draw_queue.cmds.cur_pos});
    // draw_queue.sort() // optimise draw calls ?

    self.getCurrentFrame().scene_data = draw_queue.scene_data;

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

    self.pending_batches = self.batcher.end();

    // TODO, if can't draw all in 1 batch, process max cmd as possible using a pointer to count how many commands are left
    // For now, rewind to 0
    draw_queue.cmds.rewind(0);
}

pub fn registerTexture(self: *Engine, image: Image, sampler: Sampler) !u32 {
    const slot = self.bindless_texture_count;
    self.bindless_texture_count += 1;
    try self.texture_cache.append(self.allocator, .{
        .sampler = sampler.vk_sampler,
        .image_view = image.view,
        .image_layout = .shader_read_only_optimal,
    });
    return slot;
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
