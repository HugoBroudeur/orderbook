// This is a 2D Renderer for the SDL implementation

const std = @import("std");
const sdl = @import("sdl3");
const tracy = @import("tracy");

const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const zm = @import("zmath");

const UiManager = @import("../game/ui_manager.zig");
const EcsManager = @import("../game/ecs_manager.zig");
const ClayManager = @import("../game/clay_manager.zig");
const FontManager = @import("../game/font_manager.zig");
const Ecs = @import("../game/ecs/ecs.zig");
const Colors = @import("../game/colors.zig");

const Api = @import("api.zig");
const Asset = @import("asset.zig");
const Batcher = @import("batcher.zig");
const Buffer = @import("buffer.zig");
const Camera = @import("camera.zig");
const CopyPass = @import("pass.zig").CopyPass;
const RenderPass = @import("pass.zig").RenderPass;
const Data = @import("data.zig");
const GPU = @import("gpu.zig");
const GraphicCtx = @import("graphic_ctx.zig");
const Pipeline = @import("pipeline.zig");
const Sampler = @import("sampler.zig");
const Texture = @import("texture.zig");
const Window = @import("../app/window.zig");

const Renderer = @This();

pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const TextureType = enum { atlas, swapchain };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { demo, _2d, solid };

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

pub const RendererData = struct {
    pub const BATCH_SIZE_QUADS: u32 = 10000;
    pub const BATCH_SIZE_VERTICES: u32 = BATCH_SIZE_QUADS * 4;
    pub const BATCH_SIZE_INDICES: u32 = BATCH_SIZE_QUADS * 6;

    // vertex_buffer: Buffer.VertexBuffer.create  (Data.D2Vertex, BATCH_SIZE_QUADS) = undefined,
    vertex_buffer: Buffer.VertexBuffer = undefined,
    index_buffer: Buffer.IndexBuffer(.u16) = undefined,
    transfer_buffer_tex: Buffer.TransferBuffer(.upload) = undefined,
    transfer_buffer_data: Buffer.TransferBuffer(.upload) = undefined,
    nearest_sampler: Sampler = undefined,
    pipelines: std.EnumArray(PipelineType, Pipeline),
    textures: std.EnumArray(TextureType, Texture),

    pub fn destroy(self: *RendererData) void {
        for (&self.pipelines.values) |*pipeline| {
            pipeline.deinit();
        }

        for (&self.textures.values, 0..) |*texture, i| {
            const key: TextureType = @enumFromInt(i);
            if (key != .swapchain) {
                texture.destroy();
            }
        }

        self.nearest_sampler.destroy();
        self.vertex_buffer.destroy();
        self.index_buffer.destroy();
        self.transfer_buffer_data.destroy();
        self.transfer_buffer_tex.destroy();
    }
};

allocator: std.mem.Allocator,

gpu: GPU = undefined,
api: Api = undefined,

font_manager: *FontManager = undefined,
clay_manager: *ClayManager = undefined,

ctx: GraphicCtx = undefined,

uniforms: Uniforms = undefined,

data: RendererData = undefined,
batcher: Batcher,

// vertex_buffer: Buffer.IVertexBuffer = undefined,

is_minimised: bool = false,

pub const RenderCtx = struct {};

pub fn init(allocator: std.mem.Allocator) !Renderer {
    return .{
        .allocator = allocator,
        .batcher = try .init(allocator),
    };
}

pub fn deinit(self: *Renderer) void {
    self.gpu.device.waitForIdle() catch |err| {
        std.log.err("[Renderer2D.deinit] Zig Error {}. SDL Error: {?s}", .{ err, sdl.errors.get() });
        unreachable;
    };
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

    self.ctx.deinit();

    self.data.destroy();

    self.api.deinit();
    self.gpu.deinit();
    self.batcher.deinit();
}

pub fn setup(
    self: *Renderer,
    window: *Window,
    font_manager: *FontManager,
    clay_manager: *ClayManager,
) !void {
    self.font_manager = font_manager;
    self.clay_manager = clay_manager;

    self.ctx = Api.createGraphicCtx(window);

    self.gpu = Api.createGPU(window) catch |err| {
        std.log.err("[Renderer2D.setup] {}: {?s}", .{ err, sdl.errors.get() });
        return err;
    };
    self.api = Api.init(&self.gpu);

    try self.initImgui();
    self.initUniform();

    self.data = try self.createRenderedData();

    // Transfer some data to GPU
    const vertices = [_]Data.Quad.Vertex{
        .{ .pos = .{ -1, 1 }, .uv = .{ 0, 0 }, .col = .{ 1, 0, 0, 1 } },
        .{ .pos = .{ 1, 1 }, .uv = .{ 1, 0 }, .col = .{ 0, 1, 0, 1 } },
        .{ .pos = .{ 1, -1 }, .uv = .{ 1, 1 }, .col = .{ 1, 0, 1, 1 } },
        .{ .pos = .{ -1, -1 }, .uv = .{ 0, 1 }, .col = .{ 1, 0, 1, 1 } },

        // .{ .pos = .{ -1, 0 }, .uv = .{ 0, 0 }, .col = .{ 1, 0, 0, 1 } },
        // .{ .pos = .{ 1, 0 }, .uv = .{ 1, 0 }, .col = .{ 0, 1, 0, 1 } },
        // .{ .pos = .{ 1, -1 }, .uv = .{ 1, 1 }, .col = .{ 1, 0, 1, 1 } },
        // .{ .pos = .{ -1, -1 }, .uv = .{ 0, 1 }, .col = .{ 1, 0, 1, 1 } },

        // .{ .pos = zm.f32x4(-1, 1, -1, 1), .uv = .{ .u = 0, .v = 0 } },
        // .{ .pos = zm.f32x4(1, 1, -1, 1), .uv = .{ .u = 1, .v = 0 } },
        // .{ .pos = zm.f32x4(1, -1, -1, 1), .uv = .{ .u = 1, .v = 1 } },
        // .{ .pos = zm.f32x4(-1, -1, -1, 1), .uv = .{ .u = 0, .v = 1 } },
    };
    const indices = [_]Data.Quad.Indice{
        0, 1, 2, 0, 2, 3,
        // 4, 5, 6, 4, 6, 7,
        // 0, 1, 2, 0, 2, 3,
    };

    const quad_bytes: []const u8 = std.mem.asBytes(&vertices) ++ std.mem.asBytes(&indices);

    try self.data.transfer_buffer_data.transferToGpu(&self.gpu, true, quad_bytes);
    try self.data.transfer_buffer_tex.transferToGpu(&self.gpu, true, self.data.textures.get(.atlas).surface.?.getPixels().?);

    var copy_pass = CopyPass.init(&self.gpu);
    copy_pass.start();

    self.data.vertex_buffer.upload(copy_pass, self.data.transfer_buffer_data, 0);
    self.data.index_buffer.upload(copy_pass, self.data.transfer_buffer_data, 128);

    self.data.transfer_buffer_tex.uploadTexture(copy_pass, self.data.textures.get(.atlas));

    copy_pass.end();
}

fn initImgui(self: *Renderer) !void {
    _ = impl_sdl3.ImGui_ImplSDL3_InitForSDLGPU(@ptrCast(self.ctx.window.ptr.value));
    var init_info: impl_sdlgpu3.ImGui_ImplSDLGPU3_InitInfo = undefined;
    init_info.Device = @ptrCast(self.gpu.device.value);

    const texture_format = try self.gpu.getSwapchainTextureFormat();
    init_info.ColorTargetFormat = @intFromEnum(texture_format.ptr);
    init_info.MSAASamples = @intFromEnum(sdl.gpu.SampleCount.no_multisampling);
    _ = impl_sdlgpu3.ImGui_ImplSDLGPU3_Init(&init_info);
}

pub fn initUniform(self: *Renderer) void {
    // Setup the uniform buffers
    const width: usize = self.ctx.window.getWidth();
    const heigth: usize = self.ctx.window.getHeigth();
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

pub fn createRenderedData(self: *Renderer) !RendererData {
    // Create all the resources
    const surface = try Asset.createSurface("assets/images/Background.jpg", .jpg);
    // defer surface.deinit();

    var data: RendererData = .{
        .pipelines = .initUndefined(),
        .textures = .initUndefined(),
    };

    const elements = [_]Buffer.BufferElement{
        Buffer.BufferElement.new(.Float2, "Position"),
        Buffer.BufferElement.new(.Float2, "TexCoord"),
        Buffer.BufferElement.new(.Float4, "Color"),
    };
    var layout: Buffer.BufferLayout(elements.len) = .init(elements);

    // data.vertex_buffer = try Buffer.VertexBuffer.create(&self.gpu, @intCast(self.batcher.getMaxVerticesCount()), layout.stride);
    // data.index_buffer = try Buffer.IndexBuffer(.u16).create(&self.gpu, @intCast(self.batcher.getMaxIndicesCount()));
    data.vertex_buffer = try Buffer.VertexBuffer.create(&self.gpu, 4, layout.stride);
    data.index_buffer = try Buffer.IndexBuffer(.u16).create(&self.gpu, 6);

    data.textures.set(.atlas, try .createFromSurface(&self.gpu, surface, .two_dimensional));
    data.nearest_sampler = try .create(&self.gpu, .nearest);

    // Create Pipelines
    const format = try self.gpu.getSwapchainTextureFormat();
    {
        const pipeline = try Pipeline.createDemoPipeline(&self.gpu, format);
        data.pipelines.set(.demo, pipeline);
    }
    {
        const pipeline = try Pipeline.create2DPipeline(&self.gpu, format, layout.interface());
        data.pipelines.set(._2d, pipeline);
    }
    {
        const pipeline = try Pipeline.createSolidPipeline(&self.gpu, format);
        data.pipelines.set(.solid, pipeline);
    }

    data.transfer_buffer_tex = try Buffer.TransferBuffer(.upload).create(&self.gpu, @intCast(data.textures.get(.atlas).surface.?.getPixels().?.len));
    data.transfer_buffer_data = try Buffer.TransferBuffer(.upload).create(&self.gpu, data.vertex_buffer.size_bytes + data.index_buffer.size_bytes);
    // data.transfer_buffer_tex = try api.createTransferBuffer(.upload, @intCast(surface.getPixels().?.len));
    // data.transfer_buffer_data = try api.createTransferBuffer(.upload, BATCH_SIZE_VERTICES * @sizeOf(Data.D2Vertex) + @sizeOf(Data.Indice) * BATCH_SIZE_INDICES);

    return data;
}

pub fn startFrame(self: *Renderer) void {
    Ecs.logger.info("[Renderer2D.startFrame]", .{});
    _ = self;

    // Mandatory start a Imgui frame binding
    impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
    impl_sdl3.ImGui_ImplSDL3_NewFrame();
}

pub fn drawFrame(self: *Renderer, draw_data: *Ecs.components.Graphics.DrawData) void {
    Ecs.logger.info("[Renderer2D.drawFrame]", .{});

    self.is_minimised = (draw_data.ui.*.DisplaySize.x <= 0.0) or (draw_data.ui.*.DisplaySize.y <= 0.0);

    self.uniforms.time.time = @floatFromInt(draw_data.time / 1000); // convert to seconds

    self.gpu.command_buffer = self.gpu.device.acquireCommandBuffer() catch {
        std.log.err("[Renderer2D.drawFrame] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.gpu.command_buffer.submit() catch {
            std.log.err("[Renderer2D.drawFrame] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    const swapchain_texture = self.gpu.acquireSwapchainTexture() catch {
        std.log.err("[Renderer2D.drawFrame] {?s}", .{sdl.errors.get()});
        self.gpu.command_buffer.cancel() catch {};
        return;
    };

    // if (swapchain_image.@"1" != self.window.getSize())

    if (swapchain_texture) |texture| {
        self.data.textures.set(.swapchain, texture);
    }

    self.drawDemo();
    self.draw2D();
    self.drawUi(draw_data);
}

fn drawDemo(self: *Renderer) void {
    const texture = self.data.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .load = .clear,
        .store = .store,
        .clear_color = Colors.Black.toSdl(),
        .texture = texture.ptr,
    };

    // Setup and start a render pass
    // var render_pass = self.api.createRenderPass();
    // render_pass.start(&.{gpu_target_info}, null);
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    const pipeline = self.data.pipelines.get(.demo);
    render_pass.bindGraphicsPipeline(pipeline.ptr);
    // render_pass.bindPipeline(&pipeline);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);
    // std.log.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);

    render_pass.drawPrimitives(3, 1, 0, 0);
}

fn drawUi(self: *Renderer, draw_data: *Ecs.components.Graphics.DrawData) void {
    const swapchain_texture = self.data.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture.ptr,
    };

    impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value));

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    self.clay_manager.renderCommands(draw_data.clay_render_cmds);

    // var pipeline = self.pipelines.get(._2d);
    // pipeline.bind(render_pass);
    // // TODO viewport
    // // TODO scisor
    // const mvp_bytes = std.mem.toBytes(self.uniforms.mvp);
    // const time_bytes = std.mem.toBytes(self.uniforms.time);
    //
    // self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);
    // self.gpu.command_buffer.pushFragmentUniformData(0, &time_bytes);
    // self.vertex_buffer.bind(render_pass);
    // self.index_buffer.bind(render_pass);
    // var texture = self.textures.get(.atlas);
    // texture.bind(render_pass, self.nearest_sampler);
    // render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.gpu.buffers.get(.ui_vertex), .offset = 0 }});
    // render_pass.bindIndexBuffer(.{ .buffer = self.gpu.buffers.get(.ui_index), .offset = 0 }, .indices_16bit);
    // render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.gpu.textures.get(.atlas), .sampler = self.gpu.samplers.get(.nearest) }});

    // render_pass.drawIndexedPrimitives(6, 2, 0, 0, 0);

    if (!self.is_minimised) {
        // Render ImGui
        impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value), @ptrCast(render_pass.value), null);
    }
}

fn draw2D(self: *Renderer) void {
    const swapchain_texture = self.data.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture.ptr,
    };

    // Setup and start a render pass
    // var render_pass = self.api.createRenderPass();
    // render_pass.start(&.{gpu_target_info}, null);
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    const pipeline = self.data.pipelines.get(._2d);
    render_pass.bindGraphicsPipeline(pipeline.ptr);
    // render_pass.bindPipeline(pipeline);
    // TODO viewport
    // TODO scisor
    const transform_bytes = std.mem.toBytes(self.uniforms.transform);
    // const time_bytes = std.mem.toBytes(self.uniforms.time);
    // std.log.debug("size {}, time {}", .{ bytes.len, uniform_buffer.time });
    // std.log.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &transform_bytes);
    // self.gpu.command_buffer.pushFragmentUniformData(0, &time_bytes);
    // render_pass.bindVertexBuffers(first_slot: u32, bindings: []const BufferBinding)
    // self.data.vertex_buffer.bind(render_pass);
    // self.data.index_buffer.bind(render_pass);
    render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.data.vertex_buffer.ptr, .offset = 0 }});
    render_pass.bindIndexBuffer(.{ .buffer = self.data.index_buffer.ptr, .offset = 0 }, .indices_16bit);
    const texture = self.data.textures.get(.atlas);
    // render_pass.bindTexture(texture, self.data.nearest_sampler);
    render_pass.bindFragmentSamplers(0, &.{.{ .texture = texture.ptr, .sampler = self.data.nearest_sampler.ptr }});

    render_pass.drawIndexedPrimitives(6, 2, 0, 0, 0);
}

pub fn drawQuad(self: *Renderer) void {
    _ = self;
    //TODO
}

pub fn drawRotatedQuad(self: *Renderer) void {
    _ = self;
    //TODO
}

pub fn beginScene(self: *Renderer, camera: Camera.Camera(.orthographic)) void {
    _ = self;
    //TODO
    std.log.debug("[Renderer2D.beginScene] Camera: {}", .{camera});

    // self.data.texture_shader.bind();
    // self.data.texture_shader.setMat4('u_viewProjection', camera.GetViewProjectionMatrix());
    // self.data.batcher.begin();
}

pub fn endScene(self: *Renderer) void {
    _ = self;
    //TODO
    std.log.debug("[Renderer2D.endScene]", .{});
}
