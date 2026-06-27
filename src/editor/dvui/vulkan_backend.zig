const std = @import("std");
const log = std.log.scoped(.dvui_vulkan_backend);
const vk = @import("vulkan");
const sdl = @import("sdl3");
const dvui = @import("dvui");
const SDLBackend = @import("sdl3gpu-backend");

const Engine = @import("../../engine/vulkan/engine.zig");
const Pipeline = @import("../../engine/vulkan/pipeline.zig");
const Sampler = @import("../../engine/vulkan/sampler.zig");
const Image = @import("../../engine/vulkan/image.zig");
const Buffer = @import("../../engine/vulkan/buffer.zig");
const Shader = @import("../../engine/vulkan/shader.zig");
const DescriptorAllocator = @import("../../engine/vulkan/descriptor.zig").DescriptorAllocator;
const DescriptorLayoutBuilder = @import("../../engine/vulkan/descriptor.zig").LayoutBuilder;
const DescriptorWriter = @import("../../engine/vulkan/descriptor.zig").DescriptorWriter;

const GraphicsBuffer = @import("../../engine/graphics/buffers.zig");

const VulkanBackend = @This();

const Vertex = GraphicsBuffer.Vertex;
const DvuiPushConstants = GraphicsBuffer.DvuiPushConstants;

const BackendTexture = struct {
    image: Image,
    descriptor_set: vk.DescriptorSet,
};

const DrawCall = struct {
    index_start: u32,
    index_count: u32,
    descriptor_set: vk.DescriptorSet, // which texture
    scissor: ?vk.Rect2D,
};

const cursor_enum_count = @typeInfo(dvui.enums.Cursor).@"enum".fields.len;

allocator: std.mem.Allocator,
io: std.Io,
engine: *Engine,

swapchain_pipeline: Pipeline,

/// R8G8B8A8_UNORM for off-screen dvui render targets
render_target_pipeline: Pipeline,

pipeline_layout: vk.PipelineLayout,
descriptor_set_layout: vk.DescriptorSetLayout,

// Shared samplers: [filter 0=linear 1=nearest][wrap_u 0=clamp 1=repeat][wrap_v 0=clamp 1=repeat]
samplers: [2][2][2]Sampler,

// Descriptor allocation for textures (pool reset on deinit, not per-set free)
desc_allocator: DescriptorAllocator,

// 1×1 white texture for untextured draws
white_texture: BackendTexture,

// Host-visible persistently-mapped vertex/index buffers
vertex_buf: Buffer,
index_buf: Buffer,
vertex_mapped: [*]Vertex,
index_mapped: [*]dvui.Vertex.Index,
vertex_cap: u32,
index_cap: u32,
vertex_len: u32 = 0,
index_len: u32 = 0,

draws: std.ArrayList(DrawCall),
textures_arena: std.heap.ArenaAllocator,

// Set by caller before win.begin()
cmd: vk.CommandBuffer = .null_handle,
swapchain_image_view: vk.ImageView = .null_handle,
swapchain_format: vk.Format = .b8g8r8a8_unorm,
render_extent: vk.Extent2D = .{ .width = 800, .height = 600 },

// Render-target support
current_render_target: ?*BackendTexture = null,

arena: std.mem.Allocator = undefined,
last_pixel_size: dvui.Size.Physical = .{ .w = 800, .h = 600 },
cursor_last: dvui.enums.Cursor = .arrow,
cursor_backing: [cursor_enum_count]?*sdl.c.SDL_Cursor = @splat(null),
cursor_backing_tried: [cursor_enum_count]bool = @splat(false),
manage_backend_tracking: dvui.Backend.Common.TrackManageBackend = .{},

pub fn init(allocator: std.mem.Allocator, io: std.Io, engine: *Engine) !VulkanBackend {
    // Descriptor set layout for set=1: binding=0 is MaterialParams (uniform buffer).
    // The dvui shader uses ParameterBlock<MaterialParams> which maps to uniform_buffer in SPIR-V.
    var layout_builder = try DescriptorLayoutBuilder.init(allocator);
    defer layout_builder.deinit();
    try layout_builder.addBinding(0, .uniform_buffer);
    try layout_builder.addBinding(0, .combined_image_sampler);
    const dsl = try layout_builder.build(engine.ctx, .{ .fragment_bit = true }, .{}, null);

    // 2. Pipeline layout: descriptor set + push constant for vertex buffer address
    const push_range = vk.PushConstantRange{
        .stage_flags = .{ .vertex_bit = true },
        .offset = 0,
        .size = @sizeOf(DvuiPushConstants),
    };

    const layouts = [_]vk.DescriptorSetLayout{
        engine.descriptor.vk_global_descriptor_set_layout,
        dsl,
    };

    const pipeline_layout = try engine.ctx.device.createPipelineLayout(&.{
        .set_layout_count = layouts.len,
        .p_set_layouts = @ptrCast(&layouts),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_range),
    }, null);

    // 3. Shaders — loaded from assets/shaders/dvui.spv same as every other shader
    var vert = try Shader.create(engine, .{ .name = "dvui.spv", .stage = .vertex });
    defer vert.destroy(engine.ctx);
    var frag = try Shader.create(engine, .{ .name = "dvui.spv", .stage = .fragment });
    defer frag.destroy(engine.ctx);

    // 4. Pipeline (swapchain format)
    var builder = try Pipeline.Builder.init(allocator);
    defer builder.deinit();
    try builder.setShaders(&vert, &frag);
    builder.setInputTopology(.triangle_list);
    builder.setPolygonMode(.fill);
    builder.setCullMode(.{}, .clockwise);
    builder.setMultisamplingNone();
    builder.enableBlendingPremultipliedAlpha();
    builder.disableDepthTest();
    builder.setColorAttachmentFormat(engine.swapchain.surface_format.format);
    builder.setDepthFormat(.undefined);
    builder.pipeline_layout = pipeline_layout;
    const pipeline = try builder.buildPipeline(engine.ctx);

    // 5. Render-target pipeline (R8G8B8A8 for off-screen dvui texture targets)
    builder.setColorAttachmentFormat(.r8g8b8a8_unorm);
    const rt_pipeline = try builder.buildPipeline(engine.ctx);

    // 6. Samplers — 8 variants via Sampler.create (after SamplerOption gains address_mode_u/v)
    var samplers: [2][2][2]Sampler = undefined;
    for ([_]Sampler.SamplerType{ .linear, .nearest }, 0..) |filter, fi| {
        for ([_]vk.SamplerAddressMode{ .clamp_to_edge, .repeat }, 0..) |mode_u, ui| {
            for ([_]vk.SamplerAddressMode{ .clamp_to_edge, .repeat }, 0..) |mode_v, vi| {
                samplers[fi][ui][vi] = try Sampler.create(engine.ctx, .{
                    .min_filter = filter,
                    .mag_filter = filter,
                    .mipmap_mode = filter,
                    .address_mode_u = mode_u,
                    .address_mode_v = mode_v,
                });
            }
        }
    }

    // 7. Descriptor allocator for textures
    var ratio = [_]DescriptorAllocator.PoolSizeRatio{
        .{ .vk_type = .uniform_buffer, .ratio = 1 },
        .{ .vk_type = .combined_image_sampler, .ratio = 1 },
    };
    const desc_allocator = try DescriptorAllocator.init(allocator, engine.ctx, 256, &ratio);

    // 8. Host-visible persistently-mapped vertex/index buffers.
    //    Vertex buffer uses shader_device_address_bit — Buffer.create auto-fetches
    //    the device address into vbuf.address.?, used in DvuiPushConstants each draw.
    //    Index buffer stays traditional (bound via cmdBindIndexBuffer).
    const INIT_VERTEX_CAP: u32 = 4000;
    const INIT_INDEX_CAP: u32 = 8000;
    const vbuf = try Buffer.create(engine.ctx, INIT_VERTEX_CAP * @sizeOf(Vertex), .{ .shader_device_address_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    const ibuf = try Buffer.create(engine.ctx, INIT_INDEX_CAP * @sizeOf(dvui.Vertex.Index), .{ .index_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
    const vmapped: [*]Vertex = @ptrCast(@alignCast(try engine.ctx.device.mapMemory(vbuf.memory, 0, vk.WHOLE_SIZE, .{})));
    const imapped: [*]dvui.Vertex.Index = @ptrCast(@alignCast(try engine.ctx.device.mapMemory(ibuf.memory, 0, vk.WHOLE_SIZE, .{})));

    var self: VulkanBackend = .{
        .allocator = allocator,
        .io = io,
        .engine = engine,
        .swapchain_pipeline = pipeline,
        .render_target_pipeline = rt_pipeline,
        .pipeline_layout = pipeline_layout,
        .descriptor_set_layout = dsl,
        .samplers = samplers,
        .desc_allocator = desc_allocator,
        .vertex_buf = vbuf,
        .index_buf = ibuf,
        .vertex_mapped = vmapped,
        .index_mapped = imapped,
        .vertex_cap = INIT_VERTEX_CAP,
        .index_cap = INIT_INDEX_CAP,
        .draws = .empty,
        .textures_arena = std.heap.ArenaAllocator.init(allocator),
        .white_texture = undefined,
    };

    // 9. White 1×1 texture
    self.white_texture = try self.createBackendTexture(&.{ 255, 255, 255, 255 }, 1, 1, .linear, .clamp_to_edge, .clamp_to_edge);

    return self;
}

pub fn deinit(self: *VulkanBackend) void {
    self.white_texture.image.destroy(self.engine.ctx);
    for (&self.samplers) |*fi| for (fi) |*ui| for (ui) |*s| s.destroy(self.engine.ctx);
    self.engine.ctx.device.unmapMemory(self.vertex_buf.memory);
    self.engine.ctx.device.unmapMemory(self.index_buf.memory);
    self.vertex_buf.destroy(self.engine.ctx);
    self.index_buf.destroy(self.engine.ctx);
    self.desc_allocator.destroy(self.engine.ctx);
    self.engine.ctx.device.destroyDescriptorSetLayout(self.descriptor_set_layout, null);
    self.engine.ctx.device.destroyPipelineLayout(self.pipeline_layout, null);
    self.swapchain_pipeline.destroy(self.engine.ctx);
    self.render_target_pipeline.destroy(self.engine.ctx);
    self.draws.deinit(self.allocator);
    self.textures_arena.deinit();
}

pub fn begin(self: *VulkanBackend, arena: std.mem.Allocator) !void {
    self.arena = arena;
    self.vertex_len = 0;
    self.index_len = 0;
    self.draws.clearRetainingCapacity();
}

pub fn drawClippedTriangles(
    self: *VulkanBackend,
    texture: ?dvui.Texture,
    vtx: []const dvui.Vertex,
    idx: []const dvui.Vertex.Index,
    maybe_clipr: ?dvui.Rect.Physical,
) !void {
    const ds = if (texture) |t|
        @as(*BackendTexture, @ptrCast(@alignCast(t.ptr))).descriptor_set
    else
        self.white_texture.descriptor_set;

    const scissor: ?vk.Rect2D = if (maybe_clipr) |r| .{
        .offset = .{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y) },
        .extent = .{ .width = @intFromFloat(r.w), .height = @intFromFloat(r.h) },
    } else null;

    // Ensure capacity (double on overflow)
    if (self.vertex_len + vtx.len > self.vertex_cap) try self.growVertexBuffer(@intCast(vtx.len));
    if (self.index_len + idx.len > self.index_cap) try self.growIndexBuffer(@intCast(idx.len));

    try self.draws.append(self.allocator, .{
        .index_start = self.index_len,
        .index_count = @intCast(idx.len),
        .descriptor_set = ds,
        .scissor = scissor,
    });

    const vertex_base: dvui.Vertex.Index = @intCast(self.vertex_len);
    const size = self.last_pixel_size;

    for (vtx) |v| {
        self.vertex_mapped[self.vertex_len] = .{
            .position = .{
                v.pos.x / size.w * 2.0 - 1.0,
                -(v.pos.y / size.h * 2.0 - 1.0),
                0,
                1,
            },
            .color = .{
                @as(f32, v.col.r) / 255.0,
                @as(f32, v.col.g) / 255.0,
                @as(f32, v.col.b) / 255.0,
                @as(f32, v.col.a) / 255.0,
            },
            .texcoord = .{ v.uv[0], v.uv[1] },
        };
        self.vertex_len += 1;
    }
    for (idx) |i| {
        self.index_mapped[self.index_len] = i + vertex_base;
        self.index_len += 1;
    }
}

pub fn end(self: *VulkanBackend) !void {
    if (self.vertex_len == 0) return;

    const cmd = self.cmd;
    const image_view = if (self.current_render_target) |rt| rt.image.view else self.swapchain_image_view;
    const active_pipeline = if (self.current_render_target != null) self.rt_pipeline else self.pipeline;

    // Begin dynamic render pass targeting the swapchain (LOAD to preserve 3D scene underneath)
    const color_attachment = vk.RenderingAttachmentInfo{
        .image_view = image_view,
        .image_layout = .color_attachment_optimal,
        .load_op = .load,
        .store_op = .store,
        .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
    };
    self.engine.ctx.device.cmdBeginRendering(cmd, &.{
        .layer_count = 1,
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.render_extent },
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment),
    });

    self.engine.ctx.device.cmdBindPipeline(cmd, .graphics, active_pipeline.vk_pipeline);

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.render_extent.width),
        .height = @floatFromInt(self.render_extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    self.engine.ctx.device.cmdSetViewport(cmd, 0, &.{viewport});

    const full_scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.render_extent,
    };

    // Vertex buffer via BDA push constant — same pattern as mesh/2D pipelines.
    // No cmdBindVertexBuffers: the shader reads vertices via the device address pointer.
    const push = DvuiPushConstants{ .vertex_address = self.vertex_buf.address.? };
    self.engine.ctx.device.cmdPushConstants(cmd, self.pipeline_layout, .{ .vertex_bit = true }, 0, @sizeOf(DvuiPushConstants), @ptrCast(&push));

    // Index buffer stays traditional
    self.engine.ctx.device.cmdBindIndexBuffer(cmd, self.index_buf.vk_buffer, 0, if (dvui.Vertex.Index == u32) .uint32 else .uint16);

    for (self.draws.items) |draw| {
        self.engine.ctx.device.cmdSetScissor(cmd, 0, &.{draw.scissor orelse full_scissor});
        self.engine.ctx.device.cmdBindDescriptorSets(cmd, .graphics, self.pipeline_layout, 0, &.{draw.descriptor_set}, null);
        self.engine.ctx.device.cmdDrawIndexed(cmd, draw.index_count, 1, draw.index_start, 0, 0);
    }

    self.engine.ctx.device.cmdEndRendering(cmd);
}

pub fn textureCreate(self: *VulkanBackend, pixels: [*]const u8, options: dvui.Texture.CreateOptions) !dvui.Texture {
    const interp: Sampler.SamplerType = if (options.interpolation == .linear) .linear else .nearest;
    const wrap_u: vk.SamplerAddressMode = if (options.wrap_u == .repeat) .repeat else .clamp_to_edge;
    const wrap_v: vk.SamplerAddressMode = if (options.wrap_v == .repeat) .repeat else .clamp_to_edge;

    const bt = try self.createBackendTexture(
        pixels[0 .. options.width * options.height * 4],
        options.width,
        options.height,
        interp,
        wrap_u,
        wrap_v,
    );

    const btp = try self.textures_arena.allocator().create(BackendTexture);
    btp.* = bt;

    return .{
        .ptr = btp,
        .width = options.width,
        .height = options.height,
        .format = options.format,
        .interpolation = options.interpolation,
        .wrap_u = options.wrap_u,
        .wrap_v = options.wrap_v,
    };
}

fn createBackendTexture(
    self: *VulkanBackend,
    pixels: []const u8,
    width: u32,
    height: u32,
    filter: Sampler.SamplerType,
    wrap_u: vk.SamplerAddressMode,
    wrap_v: vk.SamplerAddressMode,
) !BackendTexture {
    // Image.createFromBytes handles upload + transition to shader_read_only_optimal
    const image = try Image.createFromBytes(
        self.engine,
        pixels,
        .{ .width = width, .height = height, .depth = 1 },
        .r8g8b8a8_unorm,
        .{ .sampled_bit = true },
        false,
    );

    // Allocate one descriptor set for this texture
    const ds = try self.desc_allocator.allocate(self.engine.ctx, self.descriptor_set_layout, null);

    // Write the combined_image_sampler binding
    const fi: usize = if (filter == .linear) 0 else 1;
    const ui: usize = if (wrap_u == .repeat) 1 else 0;
    const vi: usize = if (wrap_v == .repeat) 1 else 0;
    const sampler = self.samplers[fi][ui][vi].vk_sampler;

    var writer = try DescriptorWriter.init(self.allocator);
    defer writer.deinit();
    try writer.writeImage(0, image, .{ .vk_sampler = sampler }, .shader_read_only_optimal, .combined_image_sampler);
    writer.updateSet(self.engine.ctx, ds);

    return .{ .image = image, .descriptor_set = ds };
}

pub fn textureDestroy(self: *VulkanBackend, texture: dvui.Texture) void {
    const bt: *BackendTexture = @ptrCast(@alignCast(texture.ptr));
    bt.image.destroy(self.engine.ctx);
    // descriptor_set and BackendTexture allocation freed when textures_arena is reset at deinit
}

pub fn setCursor(self: *VulkanBackend, cursor: dvui.enums.Cursor) void {
    if (cursor == self.cursor_last) return;
    defer self.cursor_last = cursor;
    const new_shown_state = if (cursor == .hidden) false else if (self.cursor_last == .hidden) true else null;
    if (new_shown_state) |new_state| {
        if (self.cursorShow(new_state) == new_state) {
            log.err("Cursor shown state was out of sync", .{});
        }
        // Return early if we are hiding
        if (new_state == false) return;
    }

    const enum_int = @intFromEnum(cursor);
    const tried = self.cursor_backing_tried[enum_int];
    if (!tried) {
        self.cursor_backing_tried[enum_int] = true;
        self.cursor_backing[enum_int] = switch (cursor) {
            .arrow => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_DEFAULT),
            .ibeam => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_TEXT),
            .wait => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_WAIT),
            .wait_arrow => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_PROGRESS),
            .crosshair => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_CROSSHAIR),
            .arrow_nw_se => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_NWSE_RESIZE),
            .arrow_ne_sw => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_NESW_RESIZE),
            .arrow_w_e => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_EW_RESIZE),
            .arrow_n_s => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_NS_RESIZE),
            .arrow_all => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_MOVE),
            .bad => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_NOT_ALLOWED),
            .hand => sdl.c.SDL_CreateSystemCursor(sdl.c.SDL_SYSTEM_CURSOR_POINTER),
            .hidden => unreachable,
        };
    }

    if (self.cursor_backing[enum_int]) |cur| {
        toErr(sdl.c.SDL_SetCursor(cur), "SDL_SetCursor in setCursor") catch return;
    } else {
        log.err("setCursor \"{s}\" failed", .{@tagName(cursor)});
        logErr("SDL_CreateSystemCursor in setCursor") catch return;
    }
    self.manage_backend_tracking.check(.setCursor);
}

pub fn cursorShow(_: *VulkanBackend, value: ?bool) bool {
    const prev = sdl.c.SDL_CursorVisible();
    if (value) |val| {
        if (val) {
            if (!sdl.c.SDL_ShowCursor()) {
                logErr("SDL_ShowCursor in cursorShow") catch return false;
            }
        } else {
            if (!sdl.c.SDL_HideCursor()) {
                logErr("SDL_HideCursor in cursorShow") catch return true;
            }
        }
    }
    return prev;
}

const SDL_ERROR = bool;
const SDL_SUCCESS: SDL_ERROR = true;
inline fn toErr(res: SDL_ERROR, what: []const u8) !void {
    if (res == SDL_SUCCESS) return;
    return logErr(what);
}

inline fn logErr(what: []const u8) dvui.Backend.GenericError {
    log.err("{s} failed, error={s}", .{ what, sdl.c.SDL_GetError() });
    return dvui.Backend.GenericError.BackendError;
}

pub fn addEvent(self: *VulkanBackend, win: *dvui.Window, event: sdl.c.SDL_Event) !bool {
    switch (event.type) {
        sdl.c.SDL_EVENT_KEY_DOWN => {
            const sdl_key: i32 = @intCast(event.key.key);
            const code = SDLBackend.SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDLBackend.SDL_keymod_to_dvui(@intCast(event.key.mod));
            if (self.log_events) {
                log.debug("event KEYDOWN {any} {s} {any} {any}\n", .{ sdl_key, @tagName(code), mod, event.key.repeat });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = if (event.key.repeat) .repeat else .down,
                .mod = mod,
            });
        },

        sdl.c.SDL_EVENT_KEY_UP => {
            const sdl_key: i32 = @intCast(event.key.key);
            const code = SDLBackend.SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDLBackend.SDL_keymod_to_dvui(@intCast(event.key.mod));
            if (self.log_events) {
                log.debug("event KEYUP {any} {s} {any}\n", .{ sdl_key, @tagName(code), mod });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = .up,
                .mod = mod,
            });
        },
        sdl.c.SDL_EVENT_TEXT_INPUT => {
            const txt = std.mem.sliceTo(event.text.text, 0);
            if (self.log_events) {
                log.debug("event TEXTINPUT {s}\n", .{txt});
            }

            return try win.addEventText(.{ .text = txt });
        },
        sdl.c.SDL_EVENT_TEXT_EDITING => {
            const strlen: u8 = @intCast(sdl.c.SDL_strlen(event.edit.text));
            if (self.log_events) {
                log.debug("event TEXTEDITING {s} start {d} len {d} strlen {d}\n", .{ event.edit.text, event.edit.start, event.edit.length, strlen });
            }
            return try win.addEventText(.{ .text = event.edit.text[0..strlen], .selected = true });
        },
        sdl.c.SDL_EVENT_MOUSE_MOTION => {
            const touch = event.motion.which == sdl.c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEMOTION {d} {d}\n", .{ touch_str, event.motion.x, event.motion.y });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            // sdl gives us mouse coords in "window coords" which is kind of
            // like natural coords but ignores content scaling
            const scale = self.pixelSize().w / self.windowSize().w;

            return try win.addEventMouseMotion(.{
                .pt = .{
                    .x = event.motion.x * scale,
                    .y = event.motion.y * scale,
                },
            });
        },
        sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            const touch = event.motion.which == sdl.c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEBUTTONDOWN {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDLBackend.SDL_mouse_button_to_dvui(event.button.button), .press);
        },
        sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => {
            const touch = event.motion.which == sdl.c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEBUTTONUP {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDLBackend.SDL_mouse_button_to_dvui(event.button.button), .release);
        },
        sdl.c.SDL_EVENT_MOUSE_WHEEL => {
            // .precise added in 2.0.18
            const ticks_x = event.wheel.x;
            const ticks_y = event.wheel.y;

            if (self.log_events) {
                log.debug("event MOUSEWHEEL {d} {d} {d}\n", .{ ticks_x, ticks_y, event.wheel.which });
            }

            var ret = false;
            var mouse_type: dvui.enums.MouseType = .unknown;
            // sdl says x positive means to the right, where as y positive
            // means up, so we negate x so that down and right match
            if (ticks_x != 0) {
                if (mouse_type == .unknown) {
                    const min = win.mouseWheelBatch(.horizontal, ticks_x);
                    mouse_type = if (min == 0.1) .trackpad else .mouse;
                }
                ret = try win.addEventMouseWheel(-ticks_x * dvui.scroll_speed, .horizontal, mouse_type);
            }
            if (ticks_y != 0) {
                if (mouse_type == .unknown) {
                    const min = win.mouseWheelBatch(.vertical, ticks_y);
                    mouse_type = if (min == 0.1) .trackpad else .mouse;
                }
                ret = try win.addEventMouseWheel(ticks_y * dvui.scroll_speed, .vertical, mouse_type);
            }
            return ret;
        },
        sdl.c.SDL_EVENT_FINGER_DOWN => {
            if (self.log_events) {
                log.debug("event FINGERDOWN {d} {d} {d}\n", .{ event.tfinger.fingerID, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.{ .button = .touch0, .action = .press, .xynorm = .{ .x = event.tfinger.x, .y = event.tfinger.y } });
        },
        sdl.c.SDL_EVENT_FINGER_UP => {
            if (self.log_events) {
                log.debug("event FINGERUP {d} {d} {d}\n", .{ event.tfinger.fingerID, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.{ .button = .touch0, .action = .release, .xynorm = .{ .x = event.tfinger.x, .y = event.tfinger.y } });
        },
        sdl.c.SDL_EVENT_FINGER_MOTION => {
            if (self.log_events) {
                log.debug("event FINGERMOTION {d} {d} {d} {d} {d}\n", .{ event.tfinger.fingerID, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy });
            }

            return try win.addEventTouchMotion(.touch0, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy);
        },
        sdl.c.SDL_EVENT_WINDOW_FOCUS_GAINED => {
            if (self.log_events) {
                log.debug("event FOCUS_GAINED\n", .{});
            }
            if (dvui.accesskit_enabled and std.builtin.os.tag == .linux) {
                dvui.AccessKit.c.accesskit_unix_adapter_update_window_focus_state(win.accesskit.adapter, true);
            } else if (dvui.accesskit_enabled and std.builtin.os.tag == .macos) {
                const events = dvui.AccessKit.c.accesskit_macos_subclassing_adapter_update_view_focus_state(win.accesskit.adapter, true);
                if (events) |evts| {
                    dvui.AccessKit.c.accesskit_macos_queued_events_raise(evts);
                }
            }
            return false;
        },
        sdl.c.SDL_EVENT_WINDOW_FOCUS_LOST => {
            if (self.log_events) {
                log.debug("event FOCUS_LOST\n", .{});
            }
            if (dvui.accesskit_enabled and std.builtin.os.tag == .linux) {
                dvui.AccessKit.c.accesskit_unix_adapter_update_window_focus_state(win.accesskit.adapter, false);
            } else if (dvui.accesskit_enabled and std.builtin.os.tag == .macos) {
                const events = dvui.AccessKit.c.accesskit_macos_subclassing_adapter_update_view_focus_state(win.accesskit.adapter, false);
                if (events) |evts| {
                    dvui.AccessKit.c.accesskit_macos_queued_events_raise(evts);
                }
            }
            return false;
        },
        sdl.c.SDL_EVENT_WINDOW_SHOWN => {
            if (self.log_events) {
                log.debug("event WINDOW_SHOWN\n", .{});
            }
            if (dvui.accesskit_enabled and std.builtin.os.tag == .linux) {
                var x: i32, var y: i32 = .{ undefined, undefined };
                _ = sdl.c.SDL_GetWindowPosition(win.backend.impl.window, &x, &y);
                var w: i32, var h: i32 = .{ undefined, undefined };
                _ = sdl.c.SDL_GetWindowSize(win.backend.impl.window, &w, &h);
                var top: i32, var bot: i32, var left: i32, var right: i32 = .{ undefined, undefined, undefined, undefined };
                _ = sdl.c.SDL_GetWindowBordersSize(win.backend.impl.window, &top, &left, &bot, &right);
                const outer_bounds: dvui.AccessKit.Rect = .{ .x0 = @floatFromInt(x - left), .y0 = @floatFromInt(y - top), .x1 = @floatFromInt(x + w + right), .y1 = @floatFromInt(y + h + bot) };
                const inner_bounds: dvui.AccessKit.Rect = .{ .x0 = @floatFromInt(x), .y0 = @floatFromInt(y), .x1 = @floatFromInt(x + w), .y1 = @floatFromInt(y + h) };
                dvui.AccessKit.c.accesskit_unix_adapter_set_root_window_bounds(win.accesskit.adapter.?, outer_bounds, inner_bounds);
            }
            return false;
        },
        sdl.c.SDL_EVENT_QUIT => {
            try win.addEventApp(.{ .action = .quit });
            return false;
        },
        else => {
            if (self.log_events) {
                log.debug("unhandled SDL event type {any}\n", .{event.type});
            }
            return false;
        },
    }
}
