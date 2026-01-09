// This is a 2D Renderer for the SDL implementation

const std = @import("std");
const sdl = @import("sdl3");

const impl_sdl3 = @import("impl_sdl3");
const impl_sdlgpu3 = @import("impl_sdlgpu3");
const zm = @import("zmath");

const UiManager = @import("../game/ui_manager.zig");
const EcsManager = @import("../game/ecs_manager.zig");
const ClayManager = @import("../game/clay_manager.zig");
const FontManager = @import("../game/font_manager.zig");
const GPU = @import("gpu.zig");
const Ecs = @import("../game/ecs/ecs.zig");
const Colors = @import("../game/colors.zig");

const Api = @import("api.zig");
const GraphicCtx = @import("graphic_ctx.zig");
const Window = @import("../app/window.zig");
const Buffer = @import("buffer.zig");
const Asset = @import("asset.zig");
const Texture = @import("texture.zig");
const Sampler = @import("sampler.zig");
const Pipeline = @import("pipeline.zig");

const Renderer = @This();

pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const TextureType = enum { atlas, swapchain };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { demo, ui, solid };

const Uniforms = struct {
    ui: struct {
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

allocator: std.mem.Allocator,

gpu: GPU = undefined,
api: Api = undefined,

font_manager: *FontManager = undefined,
clay_manager: *ClayManager = undefined,

ctx: GraphicCtx = undefined,

uniforms: Uniforms = undefined,

vertex_buffer: Buffer.VertexBuffer = undefined,
index_buffer: Buffer.IndexBuffer = undefined,
transfer_buffer_tex: Buffer.TransferBuffer = undefined,
transfer_buffer_data: Buffer.TransferBuffer = undefined,
nearest_sampler: Sampler = undefined,
pipelines: std.EnumArray(PipelineType, Pipeline),
textures: std.EnumArray(TextureType, Texture),

is_minimised: bool = false,

pub const RenderCtx = struct {};

pub fn init(allocator: std.mem.Allocator) !Renderer {
    return .{
        .allocator = allocator,
        .pipelines = .initUndefined(),
        .textures = .initUndefined(),
    };
}

pub fn deinit(self: *Renderer) void {
    self.gpu.device.waitForIdle() catch |err| {
        std.log.err("[Renderer2D.deinit] Zig Error {}. SDL Error: {?s}", .{ err, sdl.errors.get() });
        unreachable;
    };
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

    for (&self.pipelines.values) |*pipeline| {
        pipeline.deinit();
    }

    for (&self.textures.values, 0..) |*texture, i| {
        const key: TextureType = @enumFromInt(i);
        if (key != .swapchain) {
            texture.deinit();
        }
    }

    self.nearest_sampler.deinit();
    self.vertex_buffer.deinit();
    self.index_buffer.deinit();
    self.transfer_buffer_data.deinit();
    self.transfer_buffer_tex.deinit();

    self.ctx.deinit();

    self.api.deinit();
    self.gpu.deinit();
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
        std.log.err("[RendererManager.setup] {}: {?s}", .{ err, sdl.errors.get() });
        return err;
    };
    self.api = Api.init(&self.gpu);

    // const t = try allocator.dupeZ(u8, title);
    // defer allocator.free(t);

    try self.initImgui();
    self.initUniform();

    // Create all the resources
    const surface = try Asset.createSurface("assets/images/Background.jpg", .jpg);
    defer surface.deinit();
    self.vertex_buffer = try self.api.createVertexBuffer(.d2);
    self.index_buffer = try self.api.createIndexBuffer(.u16);
    self.transfer_buffer_tex = try self.api.createTransferBuffer(.upload, @intCast(surface.getPixels().?.len));
    self.transfer_buffer_data = try self.api.createTransferBuffer(.upload, @sizeOf(Pipeline.D2Vertex) * Buffer.VERTEX_BUFFER_SIZE + @sizeOf(u16) * Buffer.INDEX_BUFFER_SIZE);
    self.textures.set(.atlas, try Texture.createFromSurface(&self.gpu, surface));
    self.textures.set(.swapchain, Texture.init(&self.gpu));
    self.nearest_sampler = try Sampler.createWithGpu(&self.gpu, .nearest);

    // Create Pipelines
    const format = try self.gpu.getSwapchainTextureFormat();
    {
        const pipeline = try Pipeline.createDemoPipeline(&self.gpu, format);
        self.pipelines.set(.demo, pipeline);
    }
    {
        const pipeline = try Pipeline.createUiPipeline(&self.gpu, format);
        self.pipelines.set(.ui, pipeline);
    }
    {
        const pipeline = try Pipeline.createSolidPipeline(&self.gpu, format);
        self.pipelines.set(.solid, pipeline);
    }

    // Transfer some data to GPU
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
        .ui = .{
            .scale = .{ 1, 1 },
            .translate = .{ 1, 1 },
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

pub fn startFrame(self: *Renderer) void {
    Ecs.logger.info("[RendererManager.startFrame]", .{});
    _ = self;

    // Mandatory start a Imgui frame binding
    impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
    impl_sdl3.ImGui_ImplSDL3_NewFrame();
}

pub fn drawFrame(self: *Renderer, draw_data: *Ecs.components.Graphics.DrawData) void {
    Ecs.logger.info("[RendererManager.drawFrame]", .{});

    self.is_minimised = (draw_data.ui.*.DisplaySize.x <= 0.0) or (draw_data.ui.*.DisplaySize.y <= 0.0);

    self.uniforms.time.time = @floatFromInt(draw_data.time / 1000); // convert to seconds

    self.gpu.command_buffer = self.gpu.device.acquireCommandBuffer() catch {
        std.log.err("[RendererManager.drawFrame] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.gpu.command_buffer.submit() catch {
            std.log.err("[RendererManager.drawFrame] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    const swapchain_texture = self.gpu.acquireSwapchainTexture() catch {
        std.log.err("[RendererManager.drawFrame] {?s}", .{sdl.errors.get()});
        self.gpu.command_buffer.cancel() catch {};
        return;
    };

    // if (swapchain_image.@"1" != self.window.getSize())

    if (swapchain_texture) |texture| {
        self.textures.set(.swapchain, texture);
    }

    self.drawDemo();
    self.drawUi(draw_data);
    self.drawSolid(draw_data);
}

fn drawDemo(self: *Renderer) void {
    const texture = self.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .load = .clear,
        .store = .store,
        .clear_color = Colors.Black.toSdl(),
        .texture = texture.ptr,
    };

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    var pipeline = self.pipelines.get(.demo);
    pipeline.bind(render_pass);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);
    // std.log.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);

    render_pass.drawPrimitives(3, 1, 0, 0);
}

fn drawUi(self: *Renderer, draw_data: *Ecs.components.Graphics.DrawData) void {
    const swapchain_texture = self.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture.ptr,
    };

    impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value));

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    self.clay_manager.renderCommands(draw_data.clay_render_cmds);

    var pipeline = self.pipelines.get(.ui);
    pipeline.bind(render_pass);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp);
    const time_bytes = std.mem.toBytes(self.uniforms.time);

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);
    self.gpu.command_buffer.pushFragmentUniformData(0, &time_bytes);
    self.vertex_buffer.bind(render_pass);
    self.index_buffer.bind(render_pass);
    var texture = self.textures.get(.atlas);
    texture.bind(render_pass, self.nearest_sampler);
    // render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.gpu.buffers.get(.ui_vertex), .offset = 0 }});
    // render_pass.bindIndexBuffer(.{ .buffer = self.gpu.buffers.get(.ui_index), .offset = 0 }, .indices_16bit);
    // render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.gpu.textures.get(.atlas), .sampler = self.gpu.samplers.get(.nearest) }});

    render_pass.drawIndexedPrimitives(6, 1, 0, 0, 0);

    if (!self.is_minimised) {
        // Render ImGui
        impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value), @ptrCast(render_pass.value), null);
    }
}

fn drawSolid(self: *Renderer, draw_data: *Ecs.components.Graphics.DrawData) void {
    const swapchain_texture = self.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture.ptr,
    };

    impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(draw_data.ui), @ptrCast(self.gpu.command_buffer.value));

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    self.clay_manager.renderCommands(draw_data.clay_render_cmds);

    var pipeline = self.pipelines.get(.solid);
    pipeline.bind(render_pass);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);
    const time_bytes = std.mem.toBytes(self.uniforms.time);
    // std.log.debug("size {}, time {}", .{ bytes.len, uniform_buffer.time });
    // std.log.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);
    self.gpu.command_buffer.pushFragmentUniformData(0, &time_bytes);
    self.vertex_buffer.bind(render_pass);
    self.index_buffer.bind(render_pass);
    // render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.vertex_buffer.d2.ptr, .offset = 0 }});
    // render_pass.bindIndexBuffer(.{ .buffer = self.index_buffer.u16.ptr, .offset = 0 }, .indices_16bit);
    var texture = self.textures.get(.atlas);
    texture.bind(render_pass, self.nearest_sampler);
    // render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.gpu.textures.get(.atlas), .sampler = self.gpu.samplers.get(.nearest) }});

    render_pass.drawIndexedPrimitives(6, 2, 0, 0, 0);
}
