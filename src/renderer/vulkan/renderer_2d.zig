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
const CommandPool = @import("command_pool.zig");
const Command = @import("../command.zig");
const Framebuffer = @import("framebuffer.zig");
const Logger = @import("../../core/log.zig").MaxLogs(50);
const Mesh = @import("mesh.zig");
const RenderPass = @import("render_pass.zig");
const Data = @import("../data.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");
const Pipeline = @import("pipeline.zig");
const Sampler = @import("sampler.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const Stats = @import("../stats.zig");
const Image = @import("image.zig");

const Renderer = @This();

pub const DrawPassType = enum { demo, ui, shadow, ssao, sky, solid, raycast, transparent };
pub const TransferBufferType = enum { atlas_buffer_data, atlas_texture_data };
pub const TextureType = enum { atlas, swapchain };
pub const SamplerType = enum { nearest, linear };
pub const PipelineType = enum { demo, _2d };

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

    cmd: vk.CommandBuffer = .null_handle,
    fence: vk.Fence = .null_handle,
    image_available: vk.Semaphore = .null_handle,
    render_finished: vk.Semaphore = .null_handle,

    pub fn shouldReset(self: *FrameData, ctx: *const GraphicsContext) bool {
        // log.debug("Should reset: swap {}, height {}, width {}", .{
        //     self.swapchain_state == .suboptimal,
        //     self.previous_frame_window_size.height != ctx.window.getHeight(),
        //     self.previous_frame_window_size.width != ctx.window.getWidth(),
        // });
        if (self.swapchain_state == .suboptimal) return true;

        // Test if the window has been resized
        if (self.previous_frame_window_size.height != ctx.window.getHeight()) return true;
        if (self.previous_frame_window_size.width != ctx.window.getWidth()) return true;

        return false;
    }
};

allocator: std.mem.Allocator,
stats: Stats,

ctx: *GraphicsContext,

uniforms: Uniforms = undefined,

passes: struct {
    clear: RenderPass = undefined,
    solid: RenderPass = undefined,
} = .{},
swapchain: Swapchain = undefined,
framebuffer: Framebuffer = undefined,

cmd_pool: CommandPool = undefined,
cmd_bufs: []vk.CommandBuffer = undefined,

// triangle_buffer: Buffer = undefined,
batcher_buffer: Buffer = undefined,
text_buffer: Buffer = undefined,
uniform_buffer: Buffer = undefined,

triangle_mesh: Mesh = undefined,

// nearest_sampler: Sampler = undefined,
pipelines: std.EnumArray(PipelineType, Pipeline) = .initUndefined(),
images: std.EnumArray(TextureType, Image) = .initUndefined(),

// imgui_draw_data: *ig.ImDrawData = undefined,
imgui_draw_data: *anyopaque = undefined,

batcher: Batcher,
is_minimised: bool = false,

frame_data: FrameData = .{},

const vertices = [_]Data.Quad.Vertex{
    .{ .pos = .{ 0, -0.5 }, .uv = .{ 0.5, 0 }, .col = .{ 1, 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5 }, .uv = .{ 1, 1 }, .col = .{ 0, 1, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .uv = .{ 0, 1 }, .col = .{ 0, 0, 1, 1 } },
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

    self.cmd_pool.destroy(self.ctx);

    for (&self.pipelines.values) |*pipeline| {
        pipeline.destroy(self.ctx);
    }

    for (&self.images.values, 0..) |*image, i| {
        const key: TextureType = @enumFromInt(i);
        if (key != .swapchain) {
            image.destroy(self.ctx);
        }
    }

    // self.nearest_sampler.destroy(self.ctx);

    // self.triangle_buffer.destroy(self.ctx);
    self.triangle_mesh.destroy(self.ctx);
    self.batcher_buffer.destroy(self.ctx);
    self.text_buffer.destroy(self.ctx);
    self.uniform_buffer.destroy(self.ctx);
    self.batcher.deinit();

    self.framebuffer.destroy(self.ctx);

    self.passes.clear.destroy(self.ctx);
    self.passes.solid.destroy(self.ctx);
    self.swapchain.deinit();
}

pub fn setup(self: *Renderer) !void {
    self.initUniform();

    self.swapchain = try Swapchain.init(self.ctx, self.allocator);
    self.passes.clear = try RenderPass.create(self.ctx, self.swapchain, .{});
    self.passes.solid = try RenderPass.create(self.ctx, self.swapchain, .{ .load_op = .load, .store_op = .store });

    self.cmd_pool = try CommandPool.create(self.ctx);

    self.framebuffer = try Framebuffer.create(self.ctx, self.allocator, self.passes.clear, self.swapchain);
    Logger.debug("[Renderer2D] Found {} framebuffers", .{self.framebuffer.vk_framebuffers.len});

    const surface = try Image.loadImageAsset("assets/images/Background.jpg", .array_rgba_32);
    const image = try Image.createFromSurface(self.ctx, surface, .{ .transfer_dst_bit = true, .sampled_bit = true }, .{ .device_local_bit = true });
    self.images.set(.atlas, image);
    // self.nearest_sampler = try .create(self.ctx, .nearest);

    // self.triangle_buffer = try Buffer.create(self.ctx, @sizeOf(@TypeOf(vertices)), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true }, .{ .device_local_bit = true });
    self.uniform_buffer = try Buffer.create(self.ctx, @sizeOf(@TypeOf(self.uniforms.transform)), .{ .uniform_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    try self.uniform_buffer.copyInto(self.ctx, &std.mem.toBytes(self.uniforms.transform));

    self.batcher_buffer = try Buffer.create(self.ctx, self.batcher.getTransferBufferSizeInBytes(), .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .host_coherent_bit = true, .host_visible_bit = true });

    self.text_buffer = try Buffer.create(self.ctx, @intCast(self.images.get(.atlas).size), .{ .transfer_dst_bit = true }, .{ .device_local_bit = true });

    // const quad_mesh = try Mesh.makeQuadMesh(self.ctx, &self.cmd_pool, quad_vertices, indices: [6]u16)
    self.triangle_mesh = try Mesh.makeTriangleMesh(self.ctx, &self.cmd_pool, vertices);

    // Create Pipelines
    try self.createDemoPipeline();
    try self.create2DPipeline();

    try self.text_buffer.fastTransfer(self.ctx, &self.cmd_pool, surface.getPixels().?);
    // try self.triangle_buffer.fastTransfer(self.ctx, &self.cmd_pool, &std.mem.toBytes(vertices));

    { // Create command buffers
        self.cmd_bufs = try self.allocator.alloc(vk.CommandBuffer, self.framebuffer.vk_framebuffers.len);
        errdefer self.allocator.free(self.cmd_bufs);

        try self.ctx.device.allocateCommandBuffers(&.{
            .command_pool = self.cmd_pool.vk_cmd_pool,
            .level = .primary,
            .command_buffer_count = @intCast(self.cmd_bufs.len),
        }, self.cmd_bufs.ptr);
        errdefer self.ctx.devive.freeCommandBuffers(self.cmd_pool.vk_cmd_pool, @intCast(self.cmd_bufs.len), self.cmd_bufs.ptr);
    }
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

fn fillCommandBuffers(self: *Renderer) !void {
    self.stats.startClock(.render_passes);
    defer self.stats.tickClock(.render_passes);

    for (self.cmd_bufs, self.framebuffer.vk_framebuffers) |cmdbuf, framebuffer| {
        try self.ctx.device.resetCommandBuffer(cmdbuf, .{});
        try self.ctx.device.beginCommandBuffer(cmdbuf, &.{});

        self.ctx.device.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&self.frame_data.viewport));
        self.ctx.device.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&self.frame_data.scissor));

        { // Demo
            self.ctx.device.cmdBeginRenderPass(cmdbuf, &.{
                .render_pass = self.passes.clear.vk_render_pass,
                .framebuffer = framebuffer,
                .render_area = self.frame_data.scissor,
                .clear_value_count = 1,
                .p_clear_values = @ptrCast(&self.frame_data.clear_color),
            }, .@"inline");
            defer self.ctx.device.cmdEndRenderPass(cmdbuf);

            self.ctx.device.cmdBindPipeline(cmdbuf, .graphics, self.pipelines.get(.demo).vk_pipeline);

            const offset = [_]vk.DeviceSize{0};

            std.debug.print("Drawing {} vertices\n", .{vertices.len});

            self.ctx.device.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&self.triangle_mesh.buffers.vertex), &offset);
            self.ctx.device.cmdDraw(cmdbuf, vertices.len, 1, 0, 0);
        }

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

    // Second pass: upload with cumulative offsets
    // var current_vertex_offset: u32 = 0;
    // var current_index_offset: u32 = 0;

    {
        self.stats.startClock(.transfer);
        defer self.stats.tickClock(.transfer);

        // TODO I will need to calculate the right transfer buffer size
        // for (batches, 0..) |*batch, i| {
        //     const data = batch.toBytes();
        //     const cycle = i != 0; // Cycle on first the one only
        //     self.transfer_buffer_data.transferToGpu(&self.gpu, cycle, data.vertices, current_vertex_offset) catch {
        //         Logger.err("[Renderer2D.draw] Error while transfering vertices data to GPU: {?s}", .{sdl.errors.get()});
        //         self.stats.addSkippedDraw();
        //         return;
        //     };
        //     self.transfer_buffer_data.transferToGpu(&self.gpu, true, data.indices, total_vertex_bytes + current_index_offset) catch {
        //         Logger.err("[Renderer2D.draw] Error while transfering indices data to GPU: {?s}", .{sdl.errors.get()});
        //         self.stats.addSkippedDraw();
        //         return;
        //     };
        //
        //     // Logger.info("[Renderer2D.draw] Batch uploaded - vertex offset: {}, index offset: {}", .{ current_vertex_offset, total_vertex_bytes + current_index_offset });
        //
        //     // Accumulate offsets for next batch
        //     current_vertex_offset += @intCast(data.vertices.len);
        //     current_index_offset += @intCast(data.indices.len);
        // }
    }

    {
        self.stats.startClock(.acquire_cmd_buf);
        defer self.stats.tickClock(.acquire_cmd_buf);

        const cmd_buf = self.cmd_bufs[self.swapchain.image_index];

        self.reset() catch {
            self.frame_data.swapchain_state = .suboptimal;
            self.stats.addSkippedDraw();
            return;
        };

        // We are drawing in all the framebuffers.
        // TODO: improve for triple buffering and draw over 3 frames
        // TODO: in the triangle example the buffers are filled once on setup, then only when the self.reset() is triggered (window resize or error during last frame)
        self.fillCommandBuffers() catch {
            self.frame_data.swapchain_state = .suboptimal;
            self.stats.addSkippedDraw();
            return;
        };

        {
            self.stats.startClock(.acquire_texture);
            defer self.stats.tickClock(.acquire_texture);

            // const swtext = self.gpu.acquireSwapchainTexture() catch {
            //     // self.gpu.command_buffer.cancel() catch {};
            //     submit_cmd = true;
            //     Logger.err("[Renderer2D.draw] Failed acquiring SwapchainTexture: {?s}", .{sdl.errors.get()});
            //     self.stats.addSkippedDraw();
            //     return;
            // };
            //
            // const swapchain_texture = swtext orelse {
            //     // self.gpu.command_buffer.cancel() catch {};
            //     submit_cmd = true;
            //     // Logger.err("[Renderer2D.draw] SwapchainTexture Null: {?s}", .{sdl.errors.get()});
            //     self.stats.addSkippedDraw();
            //     return;
            // };
            // self.images.set(.swapchain, swapchain_texture);
        }

        {
            self.stats.startClock(.copy_pass);
            defer self.stats.tickClock(.copy_pass);

            // const copy_pass = self.gpu.command_buffer.beginCopyPass();
            //
            // // Upload vertices: pass explicit size
            // // Logger.info("[Renderer2D.draw] Copying {} vertex bytes from offset 0", .{total_vertex_bytes});
            // self.batcher_buffer.upload(copy_pass, &self.transfer_buffer_data, 0, total_vertex_bytes, true);
            //
            // // Upload indices: pass explicit size
            // // Logger.info("[Renderer2D.draw] Copying {} index bytes from offset {}", .{ total_index_bytes, total_vertex_bytes });
            // self.index_buffer.upload(copy_pass, &self.transfer_buffer_data, total_vertex_bytes, total_index_bytes, true);
            //
            // // self.vertex_buffer.upload(copy_pass, &self.transfer_buffer_data, 0);
            // // // self.index_buffer.upload(copy_pass, &self.transfer_buffer_data, @intCast(batch.vertices.sizeInBytes()));
            // // self.index_buffer.upload(copy_pass, &self.transfer_buffer_data, 0,total_vertex_data_in_bytes);
            //
            // copy_pass.end();
        }

        // const swapchain_texture = self.textures.get(.swapchain);
        {
            self.stats.startClock(.render_passes);
            defer self.stats.tickClock(.render_passes);

            // { // RenderPass Debug Triangle
            //     self.stats.startClock(.render_pass_triangle);
            //     defer self.stats.tickClock(.render_pass_triangle);
            //     const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
            //         // .load = if (i == 0) .clear else .load,
            //         .load = .clear,
            //         .clear_color = Colors.Black.toSdl(),
            //         .store = .store,
            //         .texture = swapchain_texture.ptr,
            //     };
            //
            //     // Setup and start a render pass
            //     const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
            //     defer render_pass.end();
            //
            //     const pipeline = self.pipelines.get(.demo);
            //     render_pass.bindGraphicsPipeline(pipeline.vk_pipeline);
            //     // TODO viewport
            //     // TODO scisor
            //     const mvp_bytes = std.mem.toBytes(self.uniforms.mvp.proj_matrix);
            //
            //     self.gpu.command_buffer.pushVertexUniformData(0, &mvp_bytes);
            //
            //     self.stats.addDrawCall(3, 1);
            //     render_pass.drawPrimitives(3, 1, 0, 0);
            // }

            // { // RenderPass Quad 2D solid with text
            //     self.stats.startClock(.render_pass_2d);
            //     defer self.stats.tickClock(.render_pass_2d);
            //
            //     const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
            //         .store = .store,
            //         .load = .load,
            //         .texture = swapchain_texture.ptr,
            //     };
            //
            //     const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
            //     defer render_pass.end();
            //
            //     const pipeline = self.pipelines.get(._2d);
            //     render_pass.bindGraphicsPipeline(pipeline.ptr);
            //
            //     const transform_bytes = std.mem.toBytes(self.uniforms.transform);
            //
            //     self.gpu.command_buffer.pushVertexUniformData(0, &transform_bytes);
            //
            //     render_pass.bindVertexBuffers(0, &.{.{ .buffer = self.batcher_buffer.vk_buffer, .offset = 0 }});
            //     render_pass.bindIndexBuffer(.{ .buffer = self.index_buffer.ptr, .offset = 0 }, .indices_16bit);
            //     const texture = self.textures.get(.atlas);
            //     // render_pass.bindTexture(texture, self.data.nearest_sampler);
            //     render_pass.bindFragmentSamplers(0, &.{.{ .texture = texture.ptr, .sampler = self.nearest_sampler.ptr }});
            //
            //     { // Debug to ensure we are good
            //         const expected_index_bytes = total_indices * @sizeOf(u16);
            //         assert(total_index_bytes == expected_index_bytes);
            //     }
            //
            //     self.stats.addDrawCall(total_vertices, total_indices);
            //     render_pass.drawIndexedPrimitives(total_indices, 1, 0, 0, 0);
            //
            //     // render_pass.drawIndexedPrimitives(0, 1, 0, 0, 0);
            // }

            // { // RenderPass UI (CIMGUI)
            //     self.stats.startClock(.render_pass_ui);
            //     defer self.stats.tickClock(.render_pass_ui);
            //
            //     const gpu_target_info: sdl.gpu.ColorTargetInfo = .{
            //         .store = .store,
            //         .load = .load,
            //         .texture = swapchain_texture.ptr,
            //     };
            //
            //     impl_sdlgpu3.ImGui_ImplSDLGPU3_PrepareDrawData(@ptrCast(self.imgui_draw_data), @ptrCast(self.gpu.command_buffer.value));
            //
            //     const render_pass = self.gpu.command_buffer.beginRenderPass(&.{gpu_target_info}, null);
            //     defer render_pass.end();
            //
            //     // TODO
            //     // self.clay_manager.renderCommands(draw_data.clay_render_cmds);
            //
            //     impl_sdlgpu3.ImGui_ImplSDLGPU3_RenderDrawData(@ptrCast(self.imgui_draw_data), @ptrCast(self.gpu.command_buffer.value), @ptrCast(render_pass.value), null);
            // }
        }

        self.frame_data.swapchain_state = self.swapchain.present(cmd_buf) catch |err| blk: {
            self.stats.addSkippedDraw();
            std.debug.print("Present failed: {}\n", .{err});
            break :blk switch (err) {
                error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
                else => |narrow| return narrow,
            };
        };
        std.debug.print("Present state: {}\n", .{self.frame_data.swapchain_state});
    }
}

pub fn reset(self: *Renderer) !void {
    if (self.frame_data.shouldReset(self.ctx)) {

        // Set Swapchain + Viewport + scisors + uniform time
        self.swapchain.recreate(.{
            .width = @intCast(self.ctx.window.getWidth()),
            .height = @intCast(self.ctx.window.getHeight()),
        }) catch {
            self.stats.addSkippedDraw();
            return;
        };
        self.frame_data.viewport.width = @floatFromInt(self.swapchain.extent.width);
        self.frame_data.viewport.height = @floatFromInt(self.swapchain.extent.height);
        self.frame_data.scissor.extent = self.swapchain.extent;
        self.frame_data.previous_frame_window_size = .{ .width = @intCast(self.ctx.window.getWidth()), .height = @intCast(self.ctx.window.getHeight()) };
        self.uniforms.time.time = @floatFromInt(sdl.timer.getMillisecondsSinceInit() / 1000); // convert to seconds

        self.framebuffer.destroy(self.ctx);
        self.framebuffer = try Framebuffer.create(self.ctx, self.allocator, self.passes.clear, self.swapchain);

        // DEBUG: Print viewport/scissor
        std.debug.print("Viewport: {}x{}\n", .{
            self.frame_data.viewport.width,
            self.frame_data.viewport.height,
        });
        std.debug.print("Scissor: {}x{}\n", .{
            self.frame_data.scissor.extent.width,
            self.frame_data.scissor.extent.height,
        });

        self.resetCommandBuffers();
        try self.createCommandBuffers();
    }
}

pub fn createCommandBuffers(self: *Renderer) !void {
    self.cmd_bufs = try self.allocator.alloc(vk.CommandBuffer, self.framebuffer.vk_framebuffers.len);
    errdefer self.allocator.free(self.cmd_bufs);

    try self.ctx.device.allocateCommandBuffers(&.{
        .command_pool = self.cmd_pool.vk_cmd_pool,
        .level = .primary,
        .command_buffer_count = @intCast(self.cmd_bufs.len),
    }, self.cmd_bufs.ptr);
    errdefer self.ctx.devive.freeCommandBuffers(self.cmd_pool.vk_cmd_pool, @intCast(self.cmd_bufs.len), self.cmd_bufs.ptr);
}

pub fn resetCommandBuffers(self: *Renderer) void {
    self.ctx.device.freeCommandBuffers(self.cmd_pool.vk_cmd_pool, @truncate(self.cmd_bufs.len), self.cmd_bufs.ptr);
    self.allocator.free(self.cmd_bufs);
}

fn createDemoPipeline(self: *Renderer) !void {
    var elements = [_]Buffer.BufferElement{
        Buffer.BufferElement.new(.Float2, "Position"),
        Buffer.BufferElement.new(.Float2, "TexCoord"),
        Buffer.BufferElement.new(.Float4, "Color"),
    };
    const layout: Buffer.BufferLayout = .init(&elements);

    const pipeline = try Pipeline.create(self.ctx, .{
        .vert = "demo.spv",
        .frag = "demo.spv",
        .layout = layout,
        .config = .{},
    }, self.passes.clear);
    self.pipelines.set(.demo, pipeline);
}

fn create2DPipeline(self: *Renderer) !void {
    var elements = [_]Buffer.BufferElement{
        Buffer.BufferElement.new(.Float2, "Position"),
        Buffer.BufferElement.new(.Float2, "TexCoord"),
        Buffer.BufferElement.new(.Float4, "Color"),
    };
    const layout: Buffer.BufferLayout = .init(&elements);

    const pipeline = try Pipeline.create(self.ctx, .{
        .vert = "2d.spv",
        .frag = "2d.spv",
        .layout = layout,
        .config = .{ .num_push_constant = 1, .num_layouts = 1 },
    }, self.passes.solid);
    self.pipelines.set(._2d, pipeline);
}
