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
const Color = @import("../../primitive.zig").Color;

// const Api = @import("../backend.zig").Vulkan;
// const Api = @import("../gfx.zig").Backend(.vulkan);
const AssetLoader = @import("asset_loader.zig");
const Batcher = @import("batcher.zig");
const Buffer = @import("buffer.zig");
const Camera = @import("../camera.zig");
const Command = @import("../command.zig");
const CommandPool = @import("command_pool.zig");
const Data = @import("../data.zig");
const DescriptorAllocator = @import("descriptor.zig").DescriptorAllocator;
const DescriptorWriter = @import("descriptor.zig").DescriptorWriter;
const DescriptorLayoutBuilder = @import("descriptor.zig").LayoutBuilder;
const Framebuffer = @import("framebuffer.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");
const Image = @import("image.zig");
const Logger = @import("../../core/log.zig").MaxLogs(50);
const Mesh = @import("mesh.zig");
const Pipeline = @import("pipeline.zig");
const RenderPass = @import("render_pass.zig");
const Sampler = @import("sampler.zig");
const SceneData = @import("../command.zig").SceneData;
const Shader = @import("shader.zig");
const Stats = @import("../stats.zig");
const Swapchain = @import("swapchain.zig").Swapchain;

const Renderer = @This();

pub const GPUCommandFn = fn (vk.CommandBuffer) anyerror!void;
pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const ImageType = enum { atlas, black, white, grey, error_checker };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { triangle, compute, mesh, _2d, _2d_bis };

pub const FRAME_OVERLAP = 2;

const FrameData = struct {
    clear_color: vk.ClearValue = .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
    previous_frame_window_size: struct { width: u32, height: u32 } = .{ .width = 0, .height = 0 },
    /// Contains the state if the last swapchain got an error
    swapchain_state: Swapchain.PresentState = .optimal,
    viewport: vk.Viewport = .{ .x = 0, .y = 0, .width = 0, .height = 0, .min_depth = 0, .max_depth = 1 },
    scissor: vk.Rect2D = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .height = 0, .width = 0 } },

    cmd_pool: CommandPool = undefined,
    cmd_buf: vk.CommandBuffer = undefined,

    desc_allocator: DescriptorAllocator = undefined,

    scene_data: SceneData = .{},
    scene_data_buffer: Buffer = undefined,

    pub fn setup(self: *FrameData, ctx: *const GraphicsContext, allocator: std.mem.Allocator) !void {
        self.cmd_pool = try CommandPool.create(ctx);
        try self.createCommandBuffer(ctx);

        const frame_sizes = &[_]DescriptorAllocator.PoolSizeRatio{
            .{ .vk_type = .storage_image, .ratio = 3 },
            .{ .vk_type = .storage_buffer, .ratio = 3 },
            .{ .vk_type = .uniform_buffer, .ratio = 3 },
            .{ .vk_type = .combined_image_sampler, .ratio = 4 },
        };
        self.desc_allocator = try DescriptorAllocator.init(allocator, ctx, 1000, frame_sizes);

        self.scene_data_buffer = try Buffer.create(ctx, @sizeOf(SceneData), .{
            .uniform_buffer_bit = true,
        }, .{ .host_visible_bit = true, .device_local_bit = true });
    }

    pub fn createCommandBuffer(self: *FrameData, ctx: *const GraphicsContext) !void {
        try ctx.device.allocateCommandBuffers(&.{
            .command_pool = self.cmd_pool.vk_cmd_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&self.cmd_buf));
    }

    pub fn shouldReset(self: *FrameData, ctx: *const GraphicsContext) bool {
        if (self.swapchain_state == .suboptimal) return true;

        if (self.previous_frame_window_size.height != ctx.window.getHeight()) return true;
        if (self.previous_frame_window_size.width != ctx.window.getWidth()) return true;

        return false;
    }

    pub fn reset(self: *FrameData, ctx: *const GraphicsContext, extent: vk.Extent2D) !void {
        self.viewport.width = @floatFromInt(extent.width);
        self.viewport.height = @floatFromInt(extent.height);
        self.scissor.extent = extent;
        self.previous_frame_window_size = .{ .width = @intCast(ctx.window.getWidth()), .height = @intCast(ctx.window.getHeight()) };
        self.swapchain_state = .optimal;

        ctx.device.freeCommandBuffers(self.cmd_pool.vk_cmd_pool, 1, @ptrCast(&self.cmd_buf));
        try self.createCommandBuffer(ctx);
    }

    pub fn destroy(self: *FrameData, ctx: *const GraphicsContext) void {
        self.cmd_pool.destroy(ctx);
        self.desc_allocator.destroy(ctx);
        self.scene_data_buffer.destroy(ctx);
    }
};

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
    scene_descriptor_layout: vk.DescriptorSetLayout = undefined,

    // Used in the Mesh Shader
    vk_mesh_descriptor_set: vk.DescriptorSet = undefined,
    vk_mesh_descriptor_set_layout: vk.DescriptorSetLayout = undefined,
    vk_material_descriptor_set: vk.DescriptorSet = undefined,
    vk_material_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

    // Used in the 2D Shader
    vk_2d_descriptor_set: vk.DescriptorSet = undefined,
    vk_2d_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

    // Used in the 2D Shader
    vk_2d_full_descriptor_set: vk.DescriptorSet = undefined,
    vk_2d_full_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

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

    pub fn setup(self: *GlobalDescriptor, ctx: *const GraphicsContext, compute_img: Image, atlas_img: Image, checker_img: Image) !void {
        { // Compute image
            var builder: DescriptorLayoutBuilder = try .init(self.allocator);
            defer builder.deinit();

            try builder.addBinding(0, .storage_image);

            self.draw_image_descriptor_layout = try builder.build(ctx, .{ .compute_bit = true }, .{}, null);
            self.draw_image_descriptor = try self.desc_allocator.allocate(ctx, self.draw_image_descriptor_layout, null);

            self.writer.clear();
            try self.writer.writeImage(0, compute_img, .general, .storage_image);
            self.writer.updateSet(ctx, self.draw_image_descriptor);
        }
        { // Scene data
            var scene_desc_builder = try DescriptorLayoutBuilder.init(self.allocator);
            defer scene_desc_builder.deinit();
            try scene_desc_builder.addBinding(0, .uniform_buffer);
            // try scene_desc_builder.addBinding(1, .combined_image_sampler);
            // scene_desc_builder.bindings.items[1].descriptor_count = 3048;

            const flags: [1]vk.DescriptorBindingFlags = .{
                .{},
                // .{ .partially_bound_bit = true, .variable_descriptor_count_bit = true },
            };
            const bind_flags: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
                .binding_count = flags.len,
                .p_binding_flags = @ptrCast(&flags),
            };

            self.scene_descriptor_layout = try scene_desc_builder.build(
                ctx,
                .{ .vertex_bit = true, .fragment_bit = true },
                .{},
                @ptrCast(&bind_flags),
            );

            // self.writer.clear();
            // // try self.writer.writeImage(0, compute_img, .general, .storage_image);
            // try self.writer.writeBuffer(0, , .general, .storage_image);
            // self.writer.updateSet(ctx, self.scene_descriptor);
        }
        { // Mesh
            var mesh_desc_builder = try DescriptorLayoutBuilder.init(self.allocator);
            defer mesh_desc_builder.deinit();
            try mesh_desc_builder.addBinding(0, .uniform_buffer);
            try mesh_desc_builder.addBinding(1, .combined_image_sampler);
            mesh_desc_builder.bindings.items[1].descriptor_count = 4048;

            const flags: [2]vk.DescriptorBindingFlags = .{
                .{},
                .{ .partially_bound_bit = true, .variable_descriptor_count_bit = true },
            };
            const bind_flags: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
                .binding_count = flags.len,
                .p_binding_flags = @ptrCast(&flags),
            };

            self.vk_mesh_descriptor_set_layout = try mesh_desc_builder.build(
                ctx,
                .{ .vertex_bit = true, .fragment_bit = true },
                .{},
                &bind_flags,
            );

            // VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT requires a
            // VkDescriptorSetVariableDescriptorCountAllocateInfo at allocate time;
            // otherwise the effective count for the variable binding defaults to 0.
            const variable_count: u32 = 4048;
            const variable_count_info: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{
                .descriptor_set_count = 1,
                .p_descriptor_counts = @ptrCast(&variable_count),
            };
            self.vk_mesh_descriptor_set = try self.desc_allocator.allocate(
                ctx,
                self.vk_mesh_descriptor_set_layout,
                @ptrCast(&variable_count_info),
            );
        }
        { // Material
            var material_builder = try DescriptorLayoutBuilder.init(self.allocator);
            defer material_builder.deinit();
            try material_builder.addBinding(0, .uniform_buffer); // material.data
            self.vk_material_descriptor_set_layout = try material_builder.build(
                ctx,
                .{ .fragment_bit = true },
                .{},
                null,
            );
            self.vk_material_descriptor_set = try self.desc_allocator.allocate(ctx, self.vk_material_descriptor_set_layout, null);
            // {
            //     var writer = try Descriptor.DescriptorWriter.init(self.allocator);
            //     defer writer.deinit();

            // { // Material Data
            //     writer.clear();
            //     try writer.writeBuffer(0, self.material_buffer, self.material_buffer.size, 0, .uniform_buffer);
            //     // writer.updateSet(self.ctx, self.descriptor.vk_mesh_descriptor_set);
            //     writer.updateSet(self.ctx, self.descriptor.vk_material_descriptor_set);
            //     // }
            // }
        }
        { // 2D images (atlas)
            var _2d_desc_builder = try DescriptorLayoutBuilder.init(self.allocator);
            defer _2d_desc_builder.deinit();
            try _2d_desc_builder.addBinding(0, .combined_image_sampler);
            try _2d_desc_builder.addBinding(1, .combined_image_sampler);
            self.vk_2d_descriptor_set_layout = try _2d_desc_builder.build(ctx, .{ .fragment_bit = true }, .{}, null);
            self.vk_2d_descriptor_set = try self.desc_allocator.allocate(ctx, self.vk_2d_descriptor_set_layout, null);

            self.writer.clear();
            try self.writer.writeImage(0, atlas_img, .shader_read_only_optimal, .combined_image_sampler);
            self.writer.updateSet(ctx, self.vk_2d_descriptor_set);

            self.writer.clear();
            try self.writer.writeImage(1, checker_img, .shader_read_only_optimal, .combined_image_sampler);
            self.writer.updateSet(ctx, self.vk_2d_descriptor_set);
        }
        // {
        //     var _2d_full_desc_builder = try Descriptor.LayoutBuilder.init(self.allocator);
        //     defer _2d_full_desc_builder.deinit();
        //     try _2d_full_desc_builder.addBinding(0, .uniform_buffer); // material.data
        //     try _2d_full_desc_builder.addBinding(1, .combined_image_sampler);
        //
        //     self.vk_2d_full_descriptor_set_layout = try _2d_full_desc_builder.build(ctx, .{ .vertex_bit = true, .fragment_bit = true }, .{}, null);
        //     self.vk_2d_full_descriptor_set = try self.desc_allocator.allocate(ctx, self.vk_2d_full_descriptor_set_layout, null);
        // }
        //
        self.is_initialised = true;
    }

    pub fn destroy(self: *GlobalDescriptor, ctx: *const GraphicsContext) void {
        self.desc_allocator.destroy(ctx);
        if (self.is_initialised) {
            ctx.device.destroyDescriptorSetLayout(self.draw_image_descriptor_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.scene_descriptor_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.vk_mesh_descriptor_set_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.vk_2d_descriptor_set_layout, null);
            // ctx.device.destroyDescriptorSetLayout(self.vk_2d_full_descriptor_set_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.vk_material_descriptor_set_layout, null);
        }
        self.writer.deinit();
    }
};

allocator: std.mem.Allocator,
stats: Stats,

ctx: *const GraphicsContext,

swapchain: Swapchain = undefined,

batcher_buffer: Buffer = undefined,
text_buffer: Buffer = undefined,
material_buffer: Buffer = undefined,
// uniform_buffer: Buffer = undefined,

triangle_mesh: Mesh = undefined,
quad_mesh: Mesh = undefined,
selftest_mesh: Mesh = undefined,
cube_mesh: Mesh = undefined,
meshes: std.ArrayList(Mesh),

// Global descriptors
descriptor: GlobalDescriptor = undefined,

asset_loader: AssetLoader,
draw_image: Image = undefined,
pipelines: std.EnumArray(PipelineType, Pipeline) = .initUndefined(),
images: std.EnumArray(ImageType, Image) = .initUndefined(),
samplers: std.EnumArray(SamplerType, Sampler) = .initUndefined(),

// imgui_draw_data: *ig.ImDrawData = undefined,
imgui_draw_data: *anyopaque = undefined,

batcher: Batcher,
is_minimised: bool = false,
draw_extent: vk.Extent2D = .{ .width = 0, .height = 0 },
render_scale: f32 = 1.0,

frame_number: u64 = 0,
frame_data: [FRAME_OVERLAP]FrameData = [2]FrameData{ .{}, .{} },

pub fn init(allocator: std.mem.Allocator, ctx: *const GraphicsContext) !Renderer {
    return .{
        .allocator = allocator,
        .stats = .init(),
        .batcher = try .init(allocator),
        .ctx = ctx,
        .asset_loader = .init(allocator),
        .meshes = try .initCapacity(allocator, 0),
    };
}

pub fn deinit(self: *Renderer) void {
    self.asset_loader.deinit();

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

    self.descriptor.destroy(self.ctx);

    self.draw_image.destroy(self.ctx);
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

    // self.triangle_buffer.destroy(self.ctx);
    self.triangle_mesh.destroy(self.ctx);
    self.quad_mesh.destroy(self.ctx);
    self.selftest_mesh.destroy(self.ctx);
    self.cube_mesh.destroy(self.ctx);
    self.batcher_buffer.destroy(self.ctx);
    self.text_buffer.destroy(self.ctx);
    // self.uniform_buffer.destroy(self.ctx);
    self.material_buffer.destroy(self.ctx);
    self.batcher.deinit();

    // self.framebuffer.destroy(self.ctx);

    // self.passes.clear.destroy(self.ctx);
    // self.passes.solid.destroy(self.ctx);
    self.swapchain.deinit();
}

pub fn setup(self: *Renderer) !void {
    self.swapchain = try Swapchain.init(self.ctx, self.allocator);

    for (&self.frame_data) |*fd| {
        try fd.setup(self.ctx, self.allocator);
    }

    self.samplers.set(.nearest, try .create(self.ctx, .nearest));
    self.samplers.set(.linear, try .create(self.ctx, .linear));

    try self.createTextures();

    // self.descriptor = try GlobalDescriptor.create(self.allocator, self.ctx);
    self.descriptor = try GlobalDescriptor.init(self.allocator, self.ctx);
    try self.descriptor.setup(self.ctx, self.draw_image, self.images.get(.atlas), self.images.get(.error_checker));

    // self.triangle_buffer = try Buffer.create(self.ctx, @sizeOf(@TypeOf(vertices)), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true }, .{ .device_local_bit = true });
    // self.uniform_buffer = try Buffer.create(self.ctx, @sizeOf(@TypeOf(self.uniforms.transform)), .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    // try self.uniform_buffer.copyInto(self.ctx, &std.mem.toBytes(self.uniforms.transform), 0);

    // Material UBO: must match the GLTFMaterialData layout in the COMPILED mesh.spv,
    // which references material.data.colorTexID and metalRoughTexID even though those
    // fields are currently commented out in include/scene.slang. Std140 alignment:
    //   vec4 colorFactors  @ offset 0  (16 bytes)
    //   int  colorTexID    @ offset 16 (4 bytes)
    //   int  metalRoughTID @ offset 20 (4 bytes)
    // Pad to next 16-byte boundary → 32 bytes total.
    const MaterialData = extern struct {
        color_factors: [4]f32 align(16) = .{ 1.0, 1.0, 1.0, 1.0 },
        color_tex_id: i32 = 0,
        metal_rough_tex_id: i32 = 0,
        _pad: [2]i32 = .{ 0, 0 },
    };
    const material_data: MaterialData = .{};
    self.material_buffer = try Buffer.create(self.ctx, @sizeOf(MaterialData), .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    try self.material_buffer.copyInto(self.ctx, std.mem.asBytes(&material_data), 0);
    // Bind material_buffer into the global material descriptor (binding 0)
    self.descriptor.writer.clear();
    try self.descriptor.writer.writeBuffer(0, self.material_buffer, self.material_buffer.size, 0, .uniform_buffer);
    self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_material_descriptor_set);
    // Seed the bindless texture array at index 0 with the error_checker so any
    // material.data.colorTexID == 0 sample returns something defined.
    self.descriptor.writer.clear();
    try self.descriptor.writer.writeImage(1, self.images.get(.error_checker), .shader_read_only_optimal, .combined_image_sampler);
    self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_mesh_descriptor_set);

    self.batcher_buffer = try Buffer.create(self.ctx, self.batcher.getTransferBufferSizeInBytes(), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .host_coherent_bit = true, .host_visible_bit = true });

    self.triangle_mesh = try Mesh.makeTriangleMesh(self.allocator, self.ctx, &self.getCurrentFrame().cmd_pool, Data.triangle_vertices);

    self.quad_mesh = try Mesh.makeQuadMesh(self.allocator, self.ctx, &self.getCurrentFrame().cmd_pool, Data.quad_vertices, &Data.quad_indices);

    // Create Pipelines
    try self.createTrianglePipeline();
    try self.create2DPipeline();
    try self.create2DBisPipeline();
    try self.createMeshPipeline();
    try self.createComputePipeline();

    // try self.triangle_buffer.fastTransfer(self.ctx, &self.cmd_pool, &std.mem.toBytes(vertices));

    self.meshes = try self.asset_loader.loadMeshes(self.ctx, &self.getCurrentFrame().cmd_pool, "assets/meshes/basic.glb");

    // [SELFTEST] Hardcoded big triangle in 3D at world z=0, with bright colors.
    // Camera is at (0,0,5) looking toward -Z, so this triangle is 5 units away
    // and ~2 units across — should fill a large central portion of the screen.
    // If you see this red/green/blue triangle, the mesh pipeline is healthy.
    {
        const verts = [_]Data.Vertex{
            .{ .pos = .{ -1.0, -1.0, 0.0 }, .uv_x = 0, .normal = .{ 0, 0, 1 }, .uv_y = 0, .col = .{ 1, 0, 0, 1 } },
            .{ .pos = .{ 1.0, -1.0, 0.0 }, .uv_x = 1, .normal = .{ 0, 0, 1 }, .uv_y = 0, .col = .{ 0, 1, 0, 1 } },
            .{ .pos = .{ 0.0, 1.0, 0.0 }, .uv_x = 0.5, .normal = .{ 0, 0, 1 }, .uv_y = 1, .col = .{ 0, 0, 1, 1 } },
        };
        const idxs = [_]Data.Indice{ 0, 1, 2 };
        self.selftest_mesh = try Mesh.init(self.allocator);
        self.selftest_mesh.name = "[SELFTEST] triangle";
        try self.selftest_mesh.surfaces.append(self.allocator, .{ .start_index = 0, .count = idxs.len });
        try self.selftest_mesh.uploadMesh(self.ctx, &self.getCurrentFrame().cmd_pool, &verts, &idxs);
        std.debug.print("[SELFTEST-mesh] uploaded test triangle: vb=0x{x}, ib_count=3\n", .{self.selftest_mesh.buffers.vertex.?.address.?});
    }

    // Hand-built unit cube centered at origin (half-size = 0.5).
    // 24 vertices = 4 per face so each face can carry its own color/normal.
    // 36 indices = 6 per face (2 triangles). Winding is CCW from outside,
    // but the mesh pipeline currently has culling disabled so winding is
    // not load-bearing for visibility — it's just convention.
    {
        const h: f32 = 0.5;
        // Face colors so each face is visually distinct.
        const c_pz: [4]f32 = .{ 0.2, 0.4, 1.0, 1 }; // +Z front: blue
        const c_nz: [4]f32 = .{ 1.0, 1.0, 0.2, 1 }; // -Z back:  yellow
        const c_px: [4]f32 = .{ 1.0, 0.2, 0.2, 1 }; // +X right: red
        const c_nx: [4]f32 = .{ 0.2, 1.0, 1.0, 1 }; // -X left:  cyan
        const c_py: [4]f32 = .{ 0.2, 1.0, 0.2, 1 }; // +Y top:   green
        const c_ny: [4]f32 = .{ 1.0, 0.2, 1.0, 1 }; // -Y bot:   magenta

        const cube_verts = [_]Data.Vertex{
            // +Z (front) — normal (0,0,1)
            .{ .pos = .{ -h, -h, h }, .uv_x = 0, .normal = .{ 0, 0, 1 }, .uv_y = 0, .col = c_pz },
            .{ .pos = .{ h, -h, h }, .uv_x = 1, .normal = .{ 0, 0, 1 }, .uv_y = 0, .col = c_pz },
            .{ .pos = .{ h, h, h }, .uv_x = 1, .normal = .{ 0, 0, 1 }, .uv_y = 1, .col = c_pz },
            .{ .pos = .{ -h, h, h }, .uv_x = 0, .normal = .{ 0, 0, 1 }, .uv_y = 1, .col = c_pz },
            // -Z (back) — normal (0,0,-1)
            .{ .pos = .{ h, -h, -h }, .uv_x = 0, .normal = .{ 0, 0, -1 }, .uv_y = 0, .col = c_nz },
            .{ .pos = .{ -h, -h, -h }, .uv_x = 1, .normal = .{ 0, 0, -1 }, .uv_y = 0, .col = c_nz },
            .{ .pos = .{ -h, h, -h }, .uv_x = 1, .normal = .{ 0, 0, -1 }, .uv_y = 1, .col = c_nz },
            .{ .pos = .{ h, h, -h }, .uv_x = 0, .normal = .{ 0, 0, -1 }, .uv_y = 1, .col = c_nz },
            // +X (right) — normal (1,0,0)
            .{ .pos = .{ h, -h, h }, .uv_x = 0, .normal = .{ 1, 0, 0 }, .uv_y = 0, .col = c_px },
            .{ .pos = .{ h, -h, -h }, .uv_x = 1, .normal = .{ 1, 0, 0 }, .uv_y = 0, .col = c_px },
            .{ .pos = .{ h, h, -h }, .uv_x = 1, .normal = .{ 1, 0, 0 }, .uv_y = 1, .col = c_px },
            .{ .pos = .{ h, h, h }, .uv_x = 0, .normal = .{ 1, 0, 0 }, .uv_y = 1, .col = c_px },
            // -X (left) — normal (-1,0,0)
            .{ .pos = .{ -h, -h, -h }, .uv_x = 0, .normal = .{ -1, 0, 0 }, .uv_y = 0, .col = c_nx },
            .{ .pos = .{ -h, -h, h }, .uv_x = 1, .normal = .{ -1, 0, 0 }, .uv_y = 0, .col = c_nx },
            .{ .pos = .{ -h, h, h }, .uv_x = 1, .normal = .{ -1, 0, 0 }, .uv_y = 1, .col = c_nx },
            .{ .pos = .{ -h, h, -h }, .uv_x = 0, .normal = .{ -1, 0, 0 }, .uv_y = 1, .col = c_nx },
            // +Y (top) — normal (0,1,0)
            .{ .pos = .{ -h, h, h }, .uv_x = 0, .normal = .{ 0, 1, 0 }, .uv_y = 0, .col = c_py },
            .{ .pos = .{ h, h, h }, .uv_x = 1, .normal = .{ 0, 1, 0 }, .uv_y = 0, .col = c_py },
            .{ .pos = .{ h, h, -h }, .uv_x = 1, .normal = .{ 0, 1, 0 }, .uv_y = 1, .col = c_py },
            .{ .pos = .{ -h, h, -h }, .uv_x = 0, .normal = .{ 0, 1, 0 }, .uv_y = 1, .col = c_py },
            // -Y (bottom) — normal (0,-1,0)
            .{ .pos = .{ -h, -h, -h }, .uv_x = 0, .normal = .{ 0, -1, 0 }, .uv_y = 0, .col = c_ny },
            .{ .pos = .{ h, -h, -h }, .uv_x = 1, .normal = .{ 0, -1, 0 }, .uv_y = 0, .col = c_ny },
            .{ .pos = .{ h, -h, h }, .uv_x = 1, .normal = .{ 0, -1, 0 }, .uv_y = 1, .col = c_ny },
            .{ .pos = .{ -h, -h, h }, .uv_x = 0, .normal = .{ 0, -1, 0 }, .uv_y = 1, .col = c_ny },
        };
        const cube_idxs = [_]Data.Indice{
            0, 1, 2, 0, 2, 3, // +Z
            4, 5, 6, 4, 6, 7, // -Z
            8, 9, 10, 8, 10, 11, // +X
            12, 13, 14, 12, 14, 15, // -X
            16, 17, 18, 16, 18, 19, // +Y
            20, 21, 22, 20, 22, 23, // -Y
        };
        self.cube_mesh = try Mesh.init(self.allocator);
        self.cube_mesh.name = "[manual] cube";
        try self.cube_mesh.surfaces.append(self.allocator, .{ .start_index = 0, .count = cube_idxs.len });
        try self.cube_mesh.uploadMesh(self.ctx, &self.getCurrentFrame().cmd_pool, &cube_verts, &cube_idxs);
        std.debug.print("[cube] uploaded manual cube: vb=0x{x}, vertex_count={d}, index_count={d}\n", .{
            self.cube_mesh.buffers.vertex.?.address.?,
            cube_verts.len,
            cube_idxs.len,
        });
    }
}

pub fn createTextures(self: *Renderer) !void {
    { // Main Draw image
        self.draw_image = try Image.create(
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
            self.samplers.getPtrConst(.linear),
            // self.swapchain.surface_format.format,
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
                    self.ctx,
                    &self.getCurrentFrame().cmd_pool,
                    color,
                    .{ .height = 1, .width = 1, .depth = 1 },
                    .r8g8b8a8_unorm,
                    .{ .sampled_bit = true },
                    .{ .device_local_bit = true },
                    self.samplers.getPtrConst(.nearest),
                ));
        }
    }

    { // Checker pattern
        const m = Color.Magenta.toBytes();
        const b = Color.Black.toBytes();
        const checker_bytes = m ++ b ++ b ++ m;

        self.images.set(.error_checker, try Image.createFromBytes(
            self.ctx,
            &self.getCurrentFrame().cmd_pool,
            &checker_bytes,
            .{ .height = 2, .width = 2, .depth = 1 },
            .r8g8b8a8_unorm,
            .{ .sampled_bit = true },
            .{ .device_local_bit = true },
            self.samplers.getPtrConst(.nearest),
        ));
    }

    { // Atlas
        const surface = try Image.loadImageAsset("assets/images/Background.jpg", .array_rgba_32);
        const image = try Image.createFromSurface(
            self.ctx,
            &self.getCurrentFrame().cmd_pool,
            surface,
            .{ .sampled_bit = true },
            .{ .device_local_bit = true },
            self.samplers.getPtrConst(.linear),
        );
        self.images.set(.atlas, image);
        self.text_buffer = try Buffer.create(self.ctx, @intCast(self.images.get(.atlas).size), .{ .transfer_dst_bit = true }, .{ .device_local_bit = true });
        try self.text_buffer.fastTransfer(self.ctx, &self.getCurrentFrame().cmd_pool, surface.getPixels().?);
    }
}

pub fn getCurrentFrame(self: *Renderer) *FrameData {
    return &self.frame_data[self.frame_number % FRAME_OVERLAP];
}

fn fillCommandBuffers(self: *Renderer) !void {
    self.stats.startClock(.render_passes);
    defer self.stats.tickClock(.render_passes);

    try self.swapchain.waitForAllFences();

    const draw_image = &self.draw_image;
    const current_frame = self.getCurrentFrame();
    const cmdbuf = current_frame.cmd_buf;
    try current_frame.desc_allocator.clear(self.ctx);

    const cmd_begin_info: vk.CommandBufferBeginInfo = .{ .flags = .{ .one_time_submit_bit = true } };
    try self.ctx.device.resetCommandBuffer(cmdbuf, .{});
    try self.ctx.device.beginCommandBuffer(cmdbuf, &cmd_begin_info);

    self.ctx.device.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&current_frame.viewport));
    self.ctx.device.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&current_frame.scissor));

    draw_image.transitionToLayout(self.ctx, cmdbuf, .undefined, .general);

    self.draw_background(cmdbuf);

    draw_image.transitionToLayout(self.ctx, cmdbuf, .general, .color_attachment_optimal);

    self.images.getPtr(.atlas).transitionToLayout(self.ctx, cmdbuf, .undefined, .shader_read_only_optimal);
    // self.draw_triangle(cmdbuf);
    // [SELFTEST] Temporarily disabled draw_2d_bis to isolate the mesh against
    // the sky. If the mesh is visible, the 2D quad was over-drawing it.
    // try self.draw_2d_bis(cmdbuf);
    try self.draw_mesh(cmdbuf);

    draw_image.transitionToLayout(self.ctx, cmdbuf, .color_attachment_optimal, .transfer_src_optimal);
    Image.vkTransitionToLayout(self.swapchain.currentImage(), self.ctx, cmdbuf, .undefined, .transfer_dst_optimal);

    Image.vkCopyImageToImage(self.ctx, cmdbuf, draw_image.vk_image, self.swapchain.currentImage(), self.draw_extent, self.swapchain.extent);

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

pub fn draw_2d(self: *Renderer, cmdbuf: vk.CommandBuffer) void {
    const current_frame = self.getCurrentFrame();
    const pipeline = self.pipelines.getPtr(._2d);

    self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, pipeline.vk_pipeline);

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

    const rendering_info: vk.RenderingInfo = .{
        .layer_count = 1,
        .render_area = current_frame.scissor,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&.{color_attachment}),
    };

    // Draw quad
    const push_constant: Mesh.PushConstants2D = .{ .scale = .{ 1, 1 }, .translate = .{ 0, 0 }, .vb_address = self.quad_mesh.buffers.vertex.?.address.? };
    self.ctx.device.cmdBindIndexBuffer(cmdbuf, self.quad_mesh.buffers.index.?.vk_buffer, 0, .uint16);

    self.ctx.device.cmdPushConstants(cmdbuf, pipeline.layout, .{ .vertex_bit = true }, 0, @sizeOf(Mesh.PushConstants2D), @ptrCast(&push_constant));

    self.ctx.device.cmdBindDescriptorSets(
        cmdbuf,
        .graphics,
        pipeline.layout,
        0,
        1,
        @ptrCast(&self.descriptor.vk_2d_descriptor_set),
        0,
        null,
    );

    self.ctx.device.cmdBeginRendering(cmdbuf, &rendering_info);
    defer self.ctx.device.cmdEndRendering(cmdbuf);

    // Draw quad
    self.ctx.device.cmdDrawIndexed(cmdbuf, 6, 1, 0, 0, 0);
}

pub fn draw_2d_bis(self: *Renderer, cmdbuf: vk.CommandBuffer) !void {
    const current_frame = self.getCurrentFrame();
    const pipeline = self.pipelines.getPtr(._2d_bis);

    self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, pipeline.vk_pipeline);

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

    const rendering_info: vk.RenderingInfo = .{
        .layer_count = 1,
        .render_area = current_frame.scissor,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&.{color_attachment}),
    };

    const push_constant: Mesh.PushConstants3D = .{ .render_matrix = current_frame.scene_data.view_proj, .vb_address = self.quad_mesh.buffers.vertex.?.address.? };
    self.ctx.device.cmdBindIndexBuffer(cmdbuf, self.quad_mesh.buffers.index.?.vk_buffer, 0, .uint16);

    self.ctx.device.cmdPushConstants(cmdbuf, pipeline.layout, .{ .vertex_bit = true }, 0, @sizeOf(Mesh.PushConstants3D), @ptrCast(&push_constant));

    //  VkDescriptorSetVariableDescriptorCountAllocateInfo allocArrayInfo{.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO, .pNext = nullptr};
    //
    //  uint32_t descriptorCounts =texCache.Cache.size();
    //  allocArrayInfo.pDescriptorCounts = &descriptorCounts;
    //  allocArrayInfo.descriptorSetCount = 1;
    //create a descriptor set that binds that buffer and update it
    //    VkDescriptorSet globalDescriptor = get_current_frame()._frameDescriptors.allocate(_device, _gpuSceneDataDescriptorLayout, &allocArrayInfo);
    //
    // DescriptorWriter writer;
    // writer.write_buffer(0, gpuSceneDataBuffer.buffer, sizeof(GPUSceneData), 0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);

    // const descriptorCount: u32 = 0; // should be TextureCache.Cache.size();
    // const allocArrayInfo: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{ .descriptor_set_count = 1, .p_descriptor_counts = @ptrCast(&descriptorCount) };
    // const descriptor = try current_frame.desc_allocator.allocate(self.ctx, self.descriptor.scene_descriptor_layout, &allocArrayInfo);
    const descriptor = try current_frame.desc_allocator.allocate(self.ctx, self.descriptor.scene_descriptor_layout, null);

    self.descriptor.writer.clear();

    // Write in the Scene Data Buffer
    try current_frame.scene_data_buffer.copyInto(self.ctx, &std.mem.toBytes(current_frame.scene_data), 0);
    try self.descriptor.writer.writeBuffer(0, current_frame.scene_data_buffer, current_frame.scene_data_buffer.size, 0, .uniform_buffer);

    self.descriptor.writer.updateSet(self.ctx, descriptor);

    const sets = [_]vk.DescriptorSet{
        descriptor, // set 0
        // self.descriptor.vk_material_descriptor_set_layout, // set 1
    };

    self.ctx.device.cmdBindDescriptorSets(
        cmdbuf,
        .graphics,
        pipeline.layout,
        0,
        sets.len,
        @ptrCast(&sets),
        0,
        null,
    );

    self.ctx.device.cmdBeginRendering(cmdbuf, &rendering_info);
    defer self.ctx.device.cmdEndRendering(cmdbuf);

    // Draw quad
    self.ctx.device.cmdDrawIndexed(cmdbuf, 6, 1, 0, 0, 0);
}

pub fn draw_mesh(self: *Renderer, cmdbuf: vk.CommandBuffer) !void {
    const current_frame = self.getCurrentFrame();
    const pipeline = self.pipelines.getPtr(.mesh);

    self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, self.pipelines.get(.mesh).vk_pipeline);

    // Refresh scene data UBO inside the global mesh descriptor set.
    // The fence wait in fillCommandBuffers() guarantees the prior frame is done
    // before we rewrite this set.
    try current_frame.scene_data_buffer.copyInto(self.ctx, &std.mem.toBytes(current_frame.scene_data), 0);
    self.descriptor.writer.clear();
    try self.descriptor.writer.writeBuffer(0, current_frame.scene_data_buffer, current_frame.scene_data_buffer.size, 0, .uniform_buffer);
    self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_mesh_descriptor_set);

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

    const rendering_info: vk.RenderingInfo = .{
        .layer_count = 1,
        .render_area = current_frame.scissor,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&.{color_attachment}),
    };

    self.ctx.device.cmdBeginRendering(cmdbuf, &rendering_info);

    // {
    //     self.descriptor.writer.clear();
    //     self.descriptor.writer.writeImage(0, self.images.get(.error_checker), .general, .combined_image_sampler) catch {};
    //     self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_compute_descriptor_set);
    // }

    // Draw quad
    // const push_constant: Mesh.PushConstants2D = .{ .scale = .{ 1, 1 }, .translate = .{ 0, 0 }, .vb_address = self.quad_mesh.buffers.vertex.?.address.? };
    // self.ctx.device.cmdBindIndexBuffer(cmdbuf, self.quad_mesh.buffers.index.?.vk_buffer, 0, .uint16);

    // Draw two meshes side-by-side, both via the mesh pipeline.
    //   left  : self.selftest_mesh (single triangle, control)
    //   right : self.cube_mesh     (hand-built cube, under test)
    // The hardcoded GLB self.meshes.items[2] (Suzanne) is bypassed for now —
    // it triggers vulkan validation errors when drawn with the wrong index count.
    const targets = [_]struct { mesh: *Mesh, m: zm.Mat, max_count: ?u32 = null }{
        .{ .mesh = &self.selftest_mesh, .m = zm.Mat{
            zm.f32x4(1, 0, 0, 0),
            zm.f32x4(0, 1, 0, 0),
            zm.f32x4(0, 0, 1, 0),
            zm.f32x4(-2, 0, 0, 1),
        } },
        .{ .mesh = &self.cube_mesh, .m = zm.Mat{
            zm.f32x4(1.5, 0, 0, 0),
            zm.f32x4(0, 1.5, 0, 0),
            zm.f32x4(0, 0, 1.5, 0),
            zm.f32x4(2, 0, 0, 1),
        } },
        .{ .mesh = &self.meshes.items[2], .m = zm.identity(), .max_count = null },
    };

    // Bind descriptor sets once (same for all draws this frame).
    self.ctx.device.cmdBindDescriptorSets(cmdbuf, .graphics, pipeline.layout, 0, 1, @ptrCast(&self.descriptor.vk_mesh_descriptor_set), 0, null);
    self.ctx.device.cmdBindDescriptorSets(cmdbuf, .graphics, pipeline.layout, 1, 1, @ptrCast(&self.descriptor.vk_material_descriptor_set), 0, null);

    const dbg_once = struct {
        var fired: bool = false;
    };
    for (targets, 0..) |t, i| {
        const push_constant: Mesh.PushConstants3D = .{ .render_matrix = t.m, .vb_address = t.mesh.buffers.vertex.?.address.? };
        self.ctx.device.cmdBindIndexBuffer(cmdbuf, t.mesh.buffers.index.?.vk_buffer, 0, .uint16);
        self.ctx.device.cmdPushConstants(cmdbuf, pipeline.layout, .{ .vertex_bit = true }, 0, @sizeOf(@TypeOf(push_constant)), @ptrCast(&push_constant));
        const surface = t.mesh.surfaces.items[0];
        const draw_count = if (t.max_count) |mc| @min(surface.count, mc) else surface.count;
        self.ctx.device.cmdDrawIndexed(cmdbuf, draw_count, 1, surface.start_index, 0, 0);

        if (!dbg_once.fired) {
            std.debug.print("[DEBUG-draw {d}] mesh '{s}' vb=0x{x} ib_handle={any} count={d} start={d} m[3]={d:.2} {d:.2} {d:.2} {d:.2}\n", .{
                i,         t.mesh.name, push_constant.vb_address, t.mesh.buffers.index.?.vk_buffer, draw_count, surface.start_index,
                t.m[3][0], t.m[3][1],   t.m[3][2],                t.m[3][3],
            });
        }
    }
    dbg_once.fired = true;

    self.ctx.device.cmdEndRendering(cmdbuf);
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
        @ptrCast(&self.descriptor.draw_image_descriptor),
        0,
        null,
    );

    const group_count_x: u32 = (@max(self.draw_extent.width, 1) + 15) / 16;
    const group_count_y: u32 = (@max(self.draw_extent.height, 1) + 15) / 16;

    self.ctx.device.cmdDispatch(cmdbuf, group_count_x, group_count_y, 1);
}

pub fn flush(self: *Renderer, draw_queue: *Command.DrawQueue) void {
    Logger.debug("[Renderer2D.flush] {} Draw Commands", .{draw_queue.cmds.cur_pos});
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
        // Sync window size to all frames so the other frame in flight doesn't
        // trigger a redundant second recreate next turn.
        for (&self.frame_data) |*fd| {
            fd.previous_frame_window_size = current_frame.previous_frame_window_size;
        }
    }

    self.draw_extent = .{
        .width = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.width))) * self.render_scale),
        .height = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.height))) * self.render_scale),
    };
    current_frame.viewport.width = @floatFromInt(self.draw_extent.width);
    current_frame.viewport.height = @floatFromInt(self.draw_extent.height);
    current_frame.scissor.extent = self.draw_extent;

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
    var vert = try Shader.create(self.ctx, .{ .name = "2d.spv", .stage = .vertex });
    defer vert.destroy(self.ctx);
    var frag = try Shader.create(self.ctx, .{ .name = "2d.spv", .stage = .fragment });
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

    const push_constant_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(Mesh.PushConstants2D), .stage_flags = .{ .vertex_bit = true } };

    pipeline_builder.pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&self.descriptor.vk_2d_descriptor_set_layout),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    const pipeline = try pipeline_builder.buildPipeline(self.ctx);

    self.pipelines.set(._2d, pipeline);
}

fn create2DBisPipeline(self: *Renderer) !void {
    var vert = try Shader.create(self.ctx, .{ .name = "2d_bis.spv", .stage = .vertex });
    defer vert.destroy(self.ctx);
    var frag = try Shader.create(self.ctx, .{ .name = "2d_bis.spv", .stage = .fragment });
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

    const push_constant_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(Mesh.PushConstants3D), .stage_flags = .{ .vertex_bit = true } };

    const set_layouts = [_]vk.DescriptorSetLayout{
        self.descriptor.scene_descriptor_layout, // set 0
            // self.descriptor.vk_material_descriptor_set_layout, // set 1
    };

    pipeline_builder.pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .set_layout_count = set_layouts.len,
        .p_set_layouts = @ptrCast(&set_layouts),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    const pipeline = try pipeline_builder.buildPipeline(self.ctx);

    self.pipelines.set(._2d_bis, pipeline);
}

fn createMeshPipeline(self: *Renderer) !void {
    var vert = try Shader.create(self.ctx, .{ .name = "mesh.spv", .stage = .vertex });
    defer vert.destroy(self.ctx);
    var frag = try Shader.create(self.ctx, .{ .name = "mesh.spv", .stage = .fragment });
    defer frag.destroy(self.ctx);

    var pipeline_builder = try Pipeline.Builder.init(self.allocator);
    defer pipeline_builder.deinit();
    try pipeline_builder.setShaders(&vert, &frag);
    pipeline_builder.setInputTopology(.triangle_list);
    pipeline_builder.setPolygonMode(.fill);
    // [SELFTEST] explicitly force NO culling, and try counter-clockwise as the
    // "front face" — matches GLTF convention. This rules out winding/cull as
    // the cause of Suzanne invisibility.
    pipeline_builder.setCullMode(vk.CullModeFlags{}, .counter_clockwise);
    std.debug.print("[SELFTEST-pipeline] mesh pipeline cull_mode = {f} front_face = {}\n", .{ pipeline_builder.rasterizer.cull_mode, pipeline_builder.rasterizer.front_face });
    pipeline_builder.setMultisamplingNone();
    // pipeline_builder.disableBlending();
    pipeline_builder.enableBlendingAdditive();
    pipeline_builder.disableDepthTest();
    pipeline_builder.setColorAttachmentFormat(self.draw_image.format);
    pipeline_builder.setDepthFormat(.undefined);

    const push_constant_range: vk.PushConstantRange = .{ .offset = 0, .size = @sizeOf(Mesh.PushConstants3D), .stage_flags = .{ .vertex_bit = true } };

    const set_layouts = [_]vk.DescriptorSetLayout{
        self.descriptor.vk_mesh_descriptor_set_layout, // set 0: scene UBO + bindless textures
        self.descriptor.vk_material_descriptor_set_layout, // set 1: material UBO
    };

    pipeline_builder.pipeline_layout = try self.ctx.device.createPipelineLayout(&.{
        .set_layout_count = set_layouts.len,
        .p_set_layouts = @ptrCast(&set_layouts),
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
        .p_set_layouts = @ptrCast(&self.descriptor.draw_image_descriptor_layout),
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);

    const pipeline = try Pipeline.createComputePipeline(self.ctx, compute, pipeline_layout);

    self.pipelines.set(.compute, pipeline);
}
