const std = @import("std");
const log = std.log.scoped(.Engine);
const assert = std.debug.assert;
const sdl = @import("sdl3");
const vk = @import("vulkan");
const tracy = @import("tracy");

const zm = @import("zmath");

const UiManager = @import("../../game/ui_manager.zig");
const EcsManager = @import("../../game/ecs_manager.zig");
const materials = @import("../graphics/materials.zig");
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
const CommandPool = @import("command_pool.zig");
const Data = @import("../data.zig");
const DescriptorAllocator = @import("descriptor.zig").DescriptorAllocator;
const DescriptorWriter = @import("descriptor.zig").DescriptorWriter;
const DescriptorLayoutBuilder = @import("descriptor.zig").LayoutBuilder;
const FrameData = @import("frames.zig").FrameData;
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

const Engine = @This();

pub const GPUCommandFn = fn (vk.CommandBuffer) anyerror!void;
pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const ImageType = enum { atlas, black, white, grey, error_checker };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { compute, _2d };

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
    scene_descriptor_layout: vk.DescriptorSetLayout = undefined,

    // Used in the Mesh Shader
    vk_global_descriptor_set: vk.DescriptorSet = undefined,
    vk_mesh_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

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

    pub fn destroy(self: *GlobalDescriptor, ctx: *const GraphicsContext) void {
        self.desc_allocator.destroy(ctx);
        if (self.is_initialised) {
            ctx.device.destroyDescriptorSetLayout(self.draw_image_descriptor_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.scene_descriptor_layout, null);
            ctx.device.destroyDescriptorSetLayout(self.vk_mesh_descriptor_set_layout, null);
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

triangle_mesh: Mesh = undefined,
quad_mesh: Mesh = undefined,
selftest_mesh: Mesh = undefined,
cube_mesh: Mesh = undefined,
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

batcher: Batcher,
is_minimised: bool = false,
draw_extent: vk.Extent2D,
render_scale: f32 = 1.0,

frame_number: u64 = 0,
frame_data: [FRAME_OVERLAP]FrameData = [2]FrameData{ .{}, .{} },

// Graphics
loaded_scenes: std.array_hash_map.String(LoadedGLTF),
main_draw_context: DrawContext,
loaded_nodes: std.StringHashMap(IRenderable),
material_default_data: materials.MaterialInstance = undefined,
material_constants_buffer: Buffer = undefined,
metal_rough_material: materials.MetallicRoughness = .create(),

// Draw optimisation
last_pipeline: ?*materials.MaterialPipeline = null,
last_material: ?*materials.MaterialInstance = null,
last_index_buffer: ?*Buffer = null,

pub fn init(allocator: std.mem.Allocator, ctx: *const GraphicsContext, io: std.Io) !Engine {
    return .{
        .io = io,
        .allocator = allocator,
        .stats = .init(),
        .batcher = try .init(allocator),
        .ctx = ctx,
        .asset_loader = try .init(allocator, io),
        .main_draw_context = try .init(allocator),
        .meshes = try .initCapacity(allocator, 0),
        .loaded_nodes = .init(allocator),
        .loaded_scenes = .empty,
        .draw_extent = ctx.window.toExtend2D(),
    };
}

pub fn deinit(self: *Engine) void {
    self.ctx.device.deviceWaitIdle() catch |err| {
        Logger.err("[Engine.deinit] Error {}", .{err});
        unreachable;
    };

    for (&self.pipelines.values) |*pipeline| {
        pipeline.destroy(self.ctx);
    }
    for (&self.pipeline_layouts.values) |pipeline_layout| {
        self.ctx.device.destroyPipelineLayout(pipeline_layout, null);
    }

    for (&self.frame_data) |*fd| {
        fd.destroy(self.ctx);
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

    // self.triangle_buffer.destroy(self.ctx);
    self.triangle_mesh.destroy(self.ctx);
    self.quad_mesh.destroy(self.ctx);
    self.selftest_mesh.destroy(self.ctx);
    self.cube_mesh.destroy(self.ctx);
    self.batcher_buffer.destroy(self.ctx);
    self.text_buffer.destroy(self.ctx);
    self.material_constants_buffer.destroy(self.ctx);
    // self.uniform_buffer.destroy(self.ctx);
    self.batcher.deinit();

    self.metal_rough_material.destroy(self);
    self.loaded_nodes.deinit();
    self.main_draw_context.deinit();

    // self.framebuffer.destroy(self.ctx);

    // self.passes.clear.destroy(self.ctx);
    // self.passes.solid.destroy(self.ctx);
    self.swapchain.deinit();
}

pub fn setup(self: *Engine) !void {
    self.swapchain = try Swapchain.init(self.ctx, self.allocator);

    for (&self.frame_data) |*fd| {
        try fd.setup(self.ctx, self.allocator);
        try self.createCommandBuffers(fd);
    }

    self.samplers.set(.nearest, try .create(self.ctx, .{}));
    self.samplers.set(.linear, try .create(self.ctx, .{ .min_filter = .linear, .mag_filter = .linear, .mipmap_mode = .linear }));

    try self.createTextures();

    // self.descriptor = try GlobalDescriptor.create(self.allocator, self.ctx);
    self.descriptor = try GlobalDescriptor.init(self.allocator, self.ctx);
    try self.setupDescriptors();

    self.batcher_buffer = try Buffer.create(self.ctx, self.batcher.getTransferBufferSizeInBytes(), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .host_coherent_bit = true, .host_visible_bit = true });

    self.triangle_mesh = try Mesh.makeTriangleMesh(self.allocator, self.ctx, &self.getCurrentFrame().cmd_pool, Buffers.triangle_vertices);

    self.quad_mesh = try Mesh.makeQuadMesh(self.allocator, self.ctx, &self.getCurrentFrame().cmd_pool, Buffers.quad_vertices, &Buffers.quad_indices);

    // Create Pipelines
    try self.create2DPipeline();
    try self.metal_rough_material.buildPipeline(self);
    try self.createComputePipeline();

    self.material_constants_buffer = try materials.MetallicRoughness.createMaterialPushConstantsBuffer(self, 1);

    const scene_uniform_data: materials.MetallicRoughness.MaterialConstants = .{ .color_factors = Color.White.toVec4(), .metal_rough_factors = .{ 1, 0.5, 0, 0 }, .extra = @splat(.{ 0, 0, 0, 0 }) };
    try self.material_constants_buffer.copyInto(self.ctx, std.mem.asBytes(&scene_uniform_data), 0);

    const material_resources: materials.MetallicRoughness.MaterialResources = .{
        .color_image = self.images.get(.white),
        .color_sampler = self.samplers.get(.linear),
        .metal_rough_image = self.images.get(.white),
        .metal_rough_sampler = self.samplers.get(.linear),
        .data_buffer = self.material_constants_buffer,
    };

    self.material_default_data = try self.metal_rough_material.writeMaterial(self, .MainColor, material_resources, &self.descriptor.desc_allocator);

    // try self.triangle_buffer.fastTransfer(self.ctx, &self.cmd_pool, &std.mem.toBytes(vertices));

    self.meshes = try self.asset_loader.loadMeshes(self, "assets/meshes/basic.glb");
    // self.meshes = try self.asset_loader.loadMeshes(self.ctx, &self.getCurrentFrame().cmd_pool, "assets/meshes/city.glb");
    const structure_file = try self.asset_loader.loadGLTFAsset(self, "assets/meshes/structure.glb");
    try self.loaded_scenes.put(self.allocator, "structure", structure_file);

    for (self.meshes.items) |*mesh| {
        const node_ptr = try self.allocator.create(MeshNode);
        node_ptr.* = try MeshNode.init(self.allocator);
        node_ptr.mesh = mesh;

        for (mesh.surfaces.items) |*s| {
            const mat = try self.allocator.create(Mesh.GLTFMaterial);
            mat.* = .{ .data = self.material_default_data };
            s.material = mat;
        }

        try self.loaded_nodes.put(mesh.name, node_ptr.interface());
        log.info("Loaded node: {s}", .{mesh.name});
    }

    // [SELFTEST] Hardcoded big triangle in 3D at world z=0, with bright colors.
    // Camera is at (0,0,5) looking toward -Z, so this triangle is 5 units away
    // and ~2 units across — should fill a large central portion of the screen.
    // If you see this red/green/blue triangle, the mesh pipeline is healthy.
    {
        const verts = [_]Vertex{
            .{ .pos = .{ -1.0, -1.0, 0.0 }, .uv_x = 0, .normal = .{ 0, 0, 1 }, .uv_y = 0, .col = .{ 1, 0, 0, 1 } },
            .{ .pos = .{ 1.0, -1.0, 0.0 }, .uv_x = 1, .normal = .{ 0, 0, 1 }, .uv_y = 0, .col = .{ 0, 1, 0, 1 } },
            .{ .pos = .{ 0.0, 1.0, 0.0 }, .uv_x = 0.5, .normal = .{ 0, 0, 1 }, .uv_y = 1, .col = .{ 0, 0, 1, 1 } },
        };
        const idxs = [_]Data.Indice{ 0, 1, 2 };
        self.selftest_mesh = try Mesh.init(self.allocator);
        self.selftest_mesh.name = "[SELFTEST] triangle";
        try self.selftest_mesh.surfaces.append(self.allocator, .{ .start_index = 0, .count = idxs.len });
        try self.selftest_mesh.uploadMesh(self, &verts, &idxs);
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

        const cube_verts = [_]Vertex{
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
        try self.cube_mesh.uploadMesh(self, &cube_verts, &cube_idxs);
        std.debug.print("[cube] uploaded manual cube: vb=0x{x}, vertex_count={d}, index_count={d}\n", .{
            self.cube_mesh.buffers.vertex.?.address.?,
            cube_verts.len,
            cube_idxs.len,
        });
    }
}

pub fn createTextures(self: *Engine) !void {
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
                .width = self.draw_extent.width,
                .height = self.draw_extent.height,
                .depth = 1,
            },
            .r16g16b16a16_sfloat,
        );
    }

    { // Main Depth image
        self.depth_image = try Image.create(
            self.ctx,
            .{
                .depth_stencil_attachment_bit = true,
            },
            .{ .device_local_bit = true },
            .{
                .width = self.draw_extent.width,
                .height = self.draw_extent.height,
                .depth = 1,
            },
            .d32_sfloat,
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
                ));
        }
    }

    { // Checker pattern
        const m = Color.Magenta.toBytes();
        const b = Color.Black.toBytes();
        const checker_bytes = m ++ b ++ b ++ m;

        self.images.set(.error_checker, try Image.createFromRawBytes(
            self,
            &checker_bytes,
            .{ .height = 2, .width = 2, .depth = 1 },
            .r8g8b8a8_unorm,
            .{ .sampled_bit = true },
            .{ .device_local_bit = true },
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
            .{ .device_local_bit = true },
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

        self.descriptor.scene_descriptor_layout = try scene_desc_builder.build(
            self.ctx,
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

        self.descriptor.vk_mesh_descriptor_set_layout = try mesh_desc_builder.build(
            self.ctx,
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
        self.descriptor.vk_global_descriptor_set = try self.descriptor.desc_allocator.allocate(
            self.ctx,
            self.descriptor.vk_mesh_descriptor_set_layout,
            @ptrCast(&variable_count_info),
        );

        // Seed the bindless texture array at index 0 with the error_checker so any
        // material.data.colorTexID == 0 sample returns something defined.
        self.descriptor.writer.clear();
        try self.descriptor.writer.writeImage(1, self.images.get(.grey), self.samplers.get(.nearest), .shader_read_only_optimal, .combined_image_sampler);
        self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_global_descriptor_set);
    }
    { // 2D images (atlas)
        var _2d_desc_builder = try DescriptorLayoutBuilder.init(self.allocator);
        defer _2d_desc_builder.deinit();
        try _2d_desc_builder.addBinding(0, .combined_image_sampler);
        try _2d_desc_builder.addBinding(1, .combined_image_sampler);
        self.descriptor.vk_2d_descriptor_set_layout = try _2d_desc_builder.build(self.ctx, .{ .fragment_bit = true }, .{}, null);
        self.descriptor.vk_2d_descriptor_set = try self.descriptor.desc_allocator.allocate(self.ctx, self.descriptor.vk_2d_descriptor_set_layout, null);

        self.descriptor.writer.clear();
        try self.descriptor.writer.writeImage(0, self.images.get(.atlas), self.samplers.get(.linear), .shader_read_only_optimal, .combined_image_sampler);
        self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_2d_descriptor_set);

        self.descriptor.writer.clear();
        try self.descriptor.writer.writeImage(1, self.images.get(.error_checker), self.samplers.get(.nearest), .shader_read_only_optimal, .combined_image_sampler);
        self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_2d_descriptor_set);
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
    self.descriptor.is_initialised = true;
}

pub fn getCurrentFrame(self: *Engine) *FrameData {
    return &self.frame_data[self.frame_number % FRAME_OVERLAP];
}

fn fillCommandBuffers(self: *Engine) !void {
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

    // self.ctx.device.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&current_frame.viewport));
    // self.ctx.device.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&current_frame.scissor));
    //
    draw_image.transitionToLayout(self.ctx, cmdbuf, .undefined, .general);

    self.draw_background(cmdbuf);

    draw_image.transitionToLayout(self.ctx, cmdbuf, .general, .color_attachment_optimal);

    self.images.getPtr(.atlas).transitionToLayout(self.ctx, cmdbuf, .undefined, .shader_read_only_optimal);

    try self.draw_context(cmdbuf);

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

pub fn createCommandBuffers(self: *Engine, frame: *FrameData) !void {
    try self.ctx.device.allocateCommandBuffers(&.{
        .command_pool = frame.cmd_pool.vk_cmd_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&frame.cmd_buf));
}

pub fn resetCommandBuffers(self: *Engine) !void {
    var frame = self.getCurrentFrame();
    frame.swapchain_state = .optimal;

    self.ctx.device.freeCommandBuffers(frame.cmd_pool.vk_cmd_pool, &.{frame.cmd_buf});
    try self.createCommandBuffers(frame);
}

pub fn draw_context(self: *Engine, cmdbuf: vk.CommandBuffer) !void {
    const current_frame = self.getCurrentFrame();

    // Populate draw context from the scene graph each frame
    self.main_draw_context.opaque_surfaces.clearRetainingCapacity();
    var identity = zm.identity();
    // var node_it = self.loaded_nodes.valueIterator();
    // try self.loaded_nodes.get("Suzanne").?.draw(&identity, &self.main_draw_context);

    try self.loaded_scenes.getPtr("structure").?.draw(&identity, &self.main_draw_context);

    // while (node_it.next()) |renderable| {
    //     try renderable.draw(&identity, &self.main_draw_context);
    // }

    // if (self.loaded_nodes.get("Cube")) |cube| {
    //     var x: i32 = -3;
    //     while (x < 1000) : (x += 1) {
    //         const scale = zm.scalingV(zm.f32x4(0.2, 0.2, 0.2, 1));
    //         const translation = zm.translationV(zm.f32x4(@floatFromInt(x), 1, 0, 0));
    //         var transform = zm.mul(scale, translation);
    //         try cube.draw(&transform, &self.main_draw_context);
    //     }
    // }

    // Refresh scene data UBO inside the global mesh descriptor set.
    // The fence wait in fillCommandBuffers() guarantees the prior frame is done
    // before we rewrite this set.
    try current_frame.scene_data_buffer.copyInto(self.ctx, &std.mem.toBytes(current_frame.scene_data), 0);
    self.descriptor.writer.clear();
    try self.descriptor.writer.writeBuffer(0, current_frame.scene_data_buffer, current_frame.scene_data_buffer.size, 0, .uniform_buffer);
    self.descriptor.writer.updateSet(self.ctx, self.descriptor.vk_global_descriptor_set);

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

    for (self.main_draw_context.opaque_surfaces.items) |*render_object| {
        self.draw_render_object(cmdbuf, render_object);
    }

    for (self.main_draw_context.transparent_surfaces.items) |*render_object| {
        self.draw_render_object(cmdbuf, render_object);
    }

    self.ctx.device.cmdEndRendering(cmdbuf);
}

fn draw_render_object(
    self: *Engine,
    cmdbuf: vk.CommandBuffer,
    ro: *RenderObject,
) void {
    const pipeline = ro.material.pipeline;

    if (ro.material != self.last_material) {
        self.last_material = ro.material;

        // rebind pipeline and descriptor if the material has changed
        if (ro.material.pipeline != self.last_pipeline) {
            self.last_pipeline = ro.material.pipeline;

            self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, pipeline.pipeline.vk_pipeline);
            self.ctx.device.cmdBindDescriptorSets(cmdbuf, .graphics, pipeline.pipeline_layout, 0, &.{self.descriptor.vk_global_descriptor_set}, null);

            self.ctx.device.cmdSetViewport(cmdbuf, 0, &.{self.getCurrentFrame().viewport});
            self.ctx.device.cmdSetScissor(cmdbuf, 0, &.{self.getCurrentFrame().scissor});
        }

        self.ctx.device.cmdBindDescriptorSets(cmdbuf, .graphics, pipeline.pipeline_layout, 1, &.{ro.material.material_set}, null);
    }

    // rebind index buffer if needed
    if (&ro.index_buffer != self.last_index_buffer) {
        self.last_index_buffer = &ro.index_buffer;
        self.ctx.device.cmdBindIndexBuffer(cmdbuf, ro.index_buffer.vk_buffer, 0, .uint32);
    }
    const push_constant: GPUDrawPushConstants = .{
        .render_matrix = ro.transform,
        .vb_address = ro.vertex_buffer.address.?,
    };

    self.ctx.device.cmdPushConstants(cmdbuf, pipeline.pipeline_layout, .{ .vertex_bit = true }, 0, @sizeOf(GPUDrawPushConstants), @ptrCast(&push_constant));
    self.ctx.device.cmdDrawIndexed(cmdbuf, ro.index_count, 1, ro.first_index, 0, 0);
}

pub fn draw_background(self: *Engine, cmdbuf: vk.CommandBuffer) void {
    // const draw_image = self.images.getPtr(.draw);
    // const current_frame = self.getCurrentFrame();

    self.ctx.device.cmdBindPipeline(cmdbuf, .compute, self.pipelines.get(.compute).vk_pipeline);
    self.ctx.device.cmdBindDescriptorSets(
        cmdbuf,
        .compute,
        self.pipeline_layouts.get(.compute),
        0,
        &.{self.descriptor.draw_image_descriptor},
        null,
    );

    const group_count_x: u32 = (@max(self.draw_extent.width, 1) + 15) / 16;
    const group_count_y: u32 = (@max(self.draw_extent.height, 1) + 15) / 16;

    self.ctx.device.cmdDispatch(cmdbuf, group_count_x, group_count_y, 1);
}

pub fn update_scene(self: *Engine, draw_queue: *Command.DrawQueue) void {
    Logger.debug("[Engine.update_scene] {} Draw Commands", .{draw_queue.cmds.cur_pos});
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

pub fn draw(self: *Engine, batches: []Batcher.Batch) !void {
    Logger.info("[Engine.draw] Drawing {} batches", .{batches.len});
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

    const cur_window_size = self.ctx.window.toExtend2D();

    if (current_frame.swapchain_state == .suboptimal or self.swapchain.isRecreateNeeded()) {
        self.swapchain.recreate(cur_window_size) catch {
            current_frame.swapchain_state = .suboptimal;
            self.stats.addSkippedDraw();
            return;
        };

        self.resetCommandBuffers() catch {
            self.stats.addSkippedDraw();
            return;
        };
    }

    self.draw_extent = .{
        .width = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.width))) * self.render_scale),
        .height = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.height))) * self.render_scale),
    };
    current_frame.resize(self.draw_extent);

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
        self.descriptor.scene_descriptor_layout, // set 0
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

fn createComputePipeline(self: *Engine) !void {
    // var compute = try Shader.create(self.ctx, .{ .name = "compute.spv", .stage = .compute });
    var compute = try Shader.create(self, .{ .name = "sky.spv", .stage = .compute });
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
    self.pipeline_layouts.set(.compute, pipeline_layout);
}
