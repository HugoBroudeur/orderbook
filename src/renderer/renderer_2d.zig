// This is a 2D Renderer for the SDL implementation

const std = @import("std");
const sdl = @import("sdl3");
const tracy = @import("tracy");

const ig = @import("cimgui");
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
const Command = @import("command.zig");
const CopyPass = @import("pass.zig").CopyPass;
const Logger = @import("../log.zig").MaxLogs(50);
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

allocator: std.mem.Allocator,

gpu: GPU = undefined,
api: Api = undefined,

font_manager: *FontManager = undefined,
clay_manager: *ClayManager = undefined,

ctx: GraphicCtx = undefined,

uniforms: Uniforms = undefined,

vertex_buffer: Buffer.VertexBuffer = undefined,
index_buffer: Buffer.IndexBuffer(.u16) = undefined,
transfer_buffer_tex: Buffer.TransferBuffer(.upload) = undefined,
transfer_buffer_data: Buffer.TransferBuffer(.upload) = undefined,
nearest_sampler: Sampler = undefined,
pipelines: std.EnumArray(PipelineType, Pipeline) = .initUndefined(),
textures: std.EnumArray(TextureType, Texture) = .initUndefined(),

imgui_draw_data: *ig.ImDrawData = undefined,

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
        Logger.err("[Renderer2D.deinit] Zig Error {}. SDL Error: {?s}", .{ err, sdl.errors.get() });
        unreachable;
    };
    impl_sdl3.ImGui_ImplSDL3_Shutdown();
    impl_sdlgpu3.ImGui_ImplSDLGPU3_Shutdown();

    self.ctx.deinit();

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
        Logger.err("[Renderer2D.setup] {}: {?s}", .{ err, sdl.errors.get() });
        return err;
    };
    self.api = Api.init(&self.gpu);

    try self.initImgui();
    self.initUniform();

    const surface = try Asset.createSurface("assets/images/Background.jpg", .jpg);
    // defer surface.deinit();

    const elements = [_]Buffer.BufferElement{
        Buffer.BufferElement.new(.Float2, "Position"),
        Buffer.BufferElement.new(.Float2, "TexCoord"),
        Buffer.BufferElement.new(.Float4, "Color"),
    };
    var layout: Buffer.BufferLayout(elements.len) = .init(elements);

    self.vertex_buffer = try .create(&self.gpu, self.batcher.getVertexBufferSizeInBytes());
    self.index_buffer = try Buffer.IndexBuffer(.u16).create(&self.gpu, self.batcher.getIndexBufferSizeInBytes());

    self.textures.set(.atlas, try .createFromSurface(&self.gpu, surface, .two_dimensional));
    self.nearest_sampler = try .create(&self.gpu, .nearest);

    // Create Pipelines
    const format = try self.gpu.getSwapchainTextureFormat();
    {
        const pipeline = try Pipeline.createDemoPipeline(&self.gpu, format);
        self.pipelines.set(.demo, pipeline);
    }
    {
        const pipeline = try Pipeline.create2DPipeline(&self.gpu, format, layout.interface());
        self.pipelines.set(._2d, pipeline);
    }
    {
        const pipeline = try Pipeline.createSolidPipeline(&self.gpu, format);
        self.pipelines.set(.solid, pipeline);
    }

    self.transfer_buffer_tex = try Buffer.TransferBuffer(.upload).create(&self.gpu, @intCast(self.textures.get(.atlas).surface.?.getPixels().?.len));

    self.transfer_buffer_data = try Buffer.TransferBuffer(.upload).create(&self.gpu, self.batcher.getTransferBufferSizeInBytes());

    // Transfer some data to GPU
    if (false) { // debug quad text
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

        try self.transfer_buffer_data.transferToGpu(&self.gpu, true, quad_bytes, 0);
    }

    try self.transfer_buffer_tex.transferToGpu(&self.gpu, true, self.textures.get(.atlas).surface.?.getPixels().?, 0);

    var copy_pass = CopyPass.init(&self.gpu);
    copy_pass.start();

    if (false) { // debug quad text
        self.vertex_buffer.upload(copy_pass, self.transfer_buffer_data, 0);
        self.index_buffer.upload(copy_pass, self.transfer_buffer_data, 128);
    }

    self.transfer_buffer_tex.uploadTexture(copy_pass, self.textures.get(.atlas));

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

pub fn startFrame(self: *Renderer) void {
    Logger.info("[Renderer2D.startFrame]", .{});
    _ = self;

    // Mandatory start a Imgui frame binding
    impl_sdlgpu3.ImGui_ImplSDLGPU3_NewFrame();
    impl_sdl3.ImGui_ImplSDL3_NewFrame();
}

pub fn drawFrame(self: *Renderer) void {
    Logger.info("[Renderer2D.drawFrame]", .{});

    // self.is_minimised = (draw_data.ui.*.DisplaySize.x <= 0.0) or (draw_data.ui.*.DisplaySize.y <= 0.0);

    self.uniforms.time.time = @floatFromInt(sdl.timer.getMillisecondsSinceInit() / 1000); // convert to seconds

    self.gpu.command_buffer = self.gpu.device.acquireCommandBuffer() catch {
        Logger.err("[Renderer2D.drawFrame] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.gpu.command_buffer.submit() catch {
            Logger.err("[Renderer2D.drawFrame] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    const swapchain_texture = self.gpu.acquireSwapchainTexture() catch {
        Logger.err("[Renderer2D.drawFrame] {?s}", .{sdl.errors.get()});
        self.gpu.command_buffer.cancel() catch {};
        return;
    };

    // if (swapchain_image.@"1" != self.window.getSize())

    if (swapchain_texture) |texture| {
        self.textures.set(.swapchain, texture);
    }

    self.drawDemo();
    self.draw2D();
    self.drawUi();
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
    // var render_pass = self.api.createRenderPass();
    // render_pass.start(&.{gpu_target_info}, null);
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    const pipeline = self.pipelines.get(.demo);
    render_pass.bindGraphicsPipeline(pipeline.ptr);
    // render_pass.bindPipeline(&pipeline);
    // TODO viewport
    // TODO scisor
    const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);
    // Logger.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);

    render_pass.drawPrimitives(3, 1, 0, 0);
}

pub fn drawUi(self: *Renderer) void {
    const swapchain_texture = self.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture.ptr,
    };

    impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(self.imgui_draw_data), @ptrCast(self.gpu.command_buffer.value));

    // Setup and start a render pass
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    // TODO
    // self.clay_manager.renderCommands(draw_data.clay_render_cmds);

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

    // Render ImGui
    impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(self.imgui_draw_data), @ptrCast(self.gpu.command_buffer.value), @ptrCast(render_pass.value), null);
}

fn draw2D(self: *Renderer) void {
    const swapchain_texture = self.textures.get(.swapchain);
    const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
        .store = .store,
        .texture = swapchain_texture.ptr,
    };

    // Setup and start a render pass
    // var render_pass = self.api.createRenderPass();
    // render_pass.start(&.{gpu_target_info}, null);
    const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
    defer render_pass.end();

    const pipeline = self.pipelines.get(._2d);
    render_pass.bindGraphicsPipeline(pipeline.ptr);
    // render_pass.bindPipeline(pipeline);
    // TODO viewport
    // TODO scisor
    const transform_bytes = std.mem.toBytes(self.uniforms.transform);
    // const time_bytes = std.mem.toBytes(self.uniforms.time);
    // Logger.debug("size {}, time {}", .{ bytes.len, uniform_buffer.time });
    // Logger.debug("size {}", .{vubo_bytes.len});

    self.gpu.command_buffer.pushVertexUniformData(0, &transform_bytes);
    // self.gpu.command_buffer.pushFragmentUniformData(0, &time_bytes);
    // render_pass.bindVertexBuffers(first_slot: u32, bindings: []const BufferBinding)
    // self.data.vertex_buffer.bind(render_pass);
    // self.data.index_buffer.bind(render_pass);
    render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.vertex_buffer.ptr, .offset = 0 }});
    render_pass.bindIndexBuffer(.{ .buffer = self.index_buffer.ptr, .offset = 0 }, .indices_16bit);
    const texture = self.textures.get(.atlas);
    // render_pass.bindTexture(texture, self.data.nearest_sampler);
    render_pass.bindFragmentSamplers(0, &.{.{ .texture = texture.ptr, .sampler = self.nearest_sampler.ptr }});

    render_pass.drawIndexedPrimitives(6, 2, 0, 0, 0);
}

pub fn drawQuadBatch(self: *Renderer, vertices: []Data.Quad.Vertex, indices: []Data.Quad.Indice) void {
    // _ = self;
    // _ = vertices;
    // _ = indices;

    const quad_bytes: []const u8 = std.mem.asBytes(vertices) ++ std.mem.asBytes(indices);

    try self.transfer_buffer_data.transferToGpu(&self.gpu, true, quad_bytes);

    var copy_pass = CopyPass.init(&self.gpu);
    copy_pass.start();

    self.vertex_buffer.upload(copy_pass, self.transfer_buffer_data, 0);
    self.index_buffer.upload(copy_pass, self.transfer_buffer_data, 128);

    copy_pass.end();
}

pub fn drawRotatedQuad(self: *Renderer) void {
    _ = self;
    //TODO
}

pub fn flush(self: *Renderer, draw_queue: *Command.DrawQueue) void {
    Logger.debug("[Renderer2D.flush] Queue size: {}", .{draw_queue.cmds.cur_pos});
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

    // TODO, if can't draw all in 1 batch, process max cmd as possible using a pointer to count how many commmands are left
    // For now, rewind to 0
    draw_queue.cmds.rewind(0);

    self.draw(batches);
}

pub fn draw(self: *Renderer, batches: []Batcher.Batch) void {
    Logger.info("[Renderer2D.draw] Drawing {} batches", .{batches.len});

    self.uniforms.time.time = @floatFromInt(sdl.timer.getMillisecondsSinceInit() / 1000); // convert to seconds

    self.gpu.command_buffer = self.gpu.device.acquireCommandBuffer() catch {
        Logger.err("[Renderer2D.draw] {?s}", .{sdl.errors.get()});
        return;
    };
    defer {
        self.gpu.command_buffer.submit() catch {
            Logger.err("[Renderer2D.draw] Command Buffer error: {?s}", .{sdl.errors.get()});
        };
    }

    const swtext = self.gpu.acquireSwapchainTexture() catch {
        Logger.err("[Renderer2D.draw] {?s}", .{sdl.errors.get()});
        self.gpu.command_buffer.cancel() catch {};
        return;
    };

    if (swtext) |texture| {
        self.textures.set(.swapchain, texture);
    }

    for (batches) |*batch| {
        { // Copy Pass just upload vertices + indexes
            const data = batch.toBytes();
            self.transfer_buffer_data.transferToGpu(&self.gpu, true, data.vertices, 0) catch {
                Logger.err("[Renderer2D.draw] Error while transfering vertices data to GPU: {?s}", .{sdl.errors.get()});
            };
            self.transfer_buffer_data.transferToGpu(&self.gpu, true, data.indices, data.vertices.len) catch {
                Logger.err("[Renderer2D.draw] Error while transfering indices data to GPU: {?s}", .{sdl.errors.get()});
            };

            var copy_pass = CopyPass.init(&self.gpu);
            copy_pass.start();

            self.vertex_buffer.upload(copy_pass, self.transfer_buffer_data, 0);
            self.index_buffer.upload(copy_pass, self.transfer_buffer_data, @intCast(batch.vertices.sizeInBytes()));

            copy_pass.end();
        }

        { // RenderPass Debug Triangle
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

            const pipeline = self.pipelines.get(.demo);
            render_pass.bindGraphicsPipeline(pipeline.ptr);
            // TODO viewport
            // TODO scisor
            const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);

            self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);

            render_pass.drawPrimitives(3, 1, 0, 0);
        }

        { // RenderPass Quad 2D solid with text
            const swapchain_texture = self.textures.get(.swapchain);
            const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
                .store = .store,
                .texture = swapchain_texture.ptr,
            };

            const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
            defer render_pass.end();

            const pipeline = self.pipelines.get(._2d);
            render_pass.bindGraphicsPipeline(pipeline.ptr);

            const transform_bytes = std.mem.toBytes(self.uniforms.transform);

            self.gpu.command_buffer.pushVertexUniformData(0, &transform_bytes);

            render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.vertex_buffer.ptr, .offset = 0 }});
            render_pass.bindIndexBuffer(.{ .buffer = self.index_buffer.ptr, .offset = 0 }, .indices_16bit);
            const texture = self.textures.get(.atlas);
            // render_pass.bindTexture(texture, self.data.nearest_sampler);
            render_pass.bindFragmentSamplers(0, &.{.{ .texture = texture.ptr, .sampler = self.nearest_sampler.ptr }});

            render_pass.drawIndexedPrimitives(batch.cur_indices, batch.cur_instances, 0, 0, 0);
        }

        { // RenderPass UI (CIMGUI)
            const swapchain_texture = self.textures.get(.swapchain);
            const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
                .store = .store,
                .texture = swapchain_texture.ptr,
            };

            impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(self.imgui_draw_data), @ptrCast(self.gpu.command_buffer.value));

            const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
            defer render_pass.end();

            // TODO
            // self.clay_manager.renderCommands(draw_data.clay_render_cmds);

            impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(self.imgui_draw_data), @ptrCast(self.gpu.command_buffer.value), @ptrCast(render_pass.value), null);
        }
    }
}
