// Central game-UI renderer. Owns the Clay context + arena, the font atlas,
// and the GPU buffers, and turns Clay's per-frame RenderCommand array into
// batched quad geometry drawn through the shared 2D pipeline (`_2d`).
//
// This is the "one central place to batch" for UI: every Clay command
// (rectangle / text / image / border / scissor) funnels through buildFrame
// into one vertex+index stream plus a list of scissor groups.

const std = @import("std");
const log = std.log.scoped(.ui);
const vk = @import("vulkan");
const clay = @import("zclay");

const Engine = @import("../vulkan/engine.zig");
const Buffer = @import("../vulkan/buffer.zig");
const Buffers = @import("buffers.zig");
const UIVertex = @import("../data.zig").UIVertex;
const FontManager = @import("font_manager.zig");

const UI = @This();

const MAX_VERTS: u32 = 65536;
const MAX_INDICES: u32 = 98304;
const FONT_PATH = "assets/fonts/SNPro/SNPro-Regular.ttf";
const FONT_SIZE: f32 = 18;

/// A run of indices sharing one scissor rect -> one draw call.
const ScissorGroup = struct {
    first_index: u32,
    index_count: u32,
    scissor: vk.Rect2D,
};

allocator: std.mem.Allocator,
font_manager: FontManager,

clay_arena: []u8 = &.{},
initialized: bool = false,

// GPU buffers (single, shared across frames — fine while UI content is static;
// make per-frame or ring-buffered before driving dynamic UI).
vertex_buffer: Buffer = undefined,
index_buffer: Buffer = undefined,

// CPU-side accumulation, rebuilt every frame.
verts: std.ArrayList(UIVertex),
indices: std.ArrayList(u16),
groups: std.ArrayList(ScissorGroup),

pub fn init(allocator: std.mem.Allocator) UI {
    return .{
        .allocator = allocator,
        .font_manager = FontManager.init(allocator),
        .verts = .empty,
        .indices = .empty,
        .groups = .empty,
    };
}

pub fn deinit(self: *UI) void {
    if (self.initialized) {
        self.vertex_buffer.destroy();
        self.index_buffer.destroy();
        self.allocator.free(self.clay_arena);
    }
    self.font_manager.deinit();
    self.verts.deinit(self.allocator);
    self.indices.deinit(self.allocator);
    self.groups.deinit(self.allocator);
}

/// Deferred one-time init. Called at the top of each frame; the first call
/// bakes the font atlas + inits Clay. Deferred (not done in Engine.setup) so
/// the resource manager registers the basic textures first and `white` keeps
/// bindless slot 0.
pub fn ensureInit(self: *UI, engine: *Engine) !void {
    if (self.initialized) return;

    try self.font_manager.load(engine, FONT_PATH, FONT_SIZE);

    self.clay_arena = try self.allocator.alignedAlloc(u8, .@"8", clay.minMemorySize());
    const arena: clay.Arena = .init(self.clay_arena);
    _ = clay.initialize(arena, .{ .w = 100, .h = 100 }, .{});
    clay.setMeasureTextFunction(*FontManager, &self.font_manager, FontManager.measureText);

    self.vertex_buffer = try Buffer.create(
        engine,
        MAX_VERTS * @sizeOf(UIVertex),
        .{ .shader_device_address_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    self.index_buffer = try Buffer.create(
        engine,
        MAX_INDICES * @sizeOf(u16),
        .{ .index_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    self.initialized = true;
    log.info("[UI] initialized (font slot {d})", .{self.font_manager.font.atlas_slot});
}

/// Build this frame's UI layout, translate it to geometry, upload it.
/// `extent` is the target surface size in pixels.
pub fn buildFrame(self: *UI, extent: vk.Extent2D) !void {
    clay.setLayoutDimensions(.{ .w = @floatFromInt(extent.width), .h = @floatFromInt(extent.height) });

    clay.beginLayout();
    buildTestLayout();
    const cmds = clay.endLayout();

    try self.translate(cmds, extent);

    if (self.verts.items.len > 0)
        try self.vertex_buffer.copyInto(std.mem.sliceAsBytes(self.verts.items), 0);
    if (self.indices.items.len > 0)
        try self.index_buffer.copyInto(std.mem.sliceAsBytes(self.indices.items), 0);
}

/// TEST layout: a padded rounded panel containing a line of text.
fn buildTestLayout() void {
    const panel: clay.Color = .{ 40, 44, 62, 255 };
    const text_col: clay.Color = .{ 235, 235, 245, 255 };

    clay.UI()(.{
        .id = .ID("Root"),
        .layout = .{ .sizing = .grow, .padding = .all(24), .child_alignment = .{ .x = .left, .y = .top } },
    })({
        clay.UI()(.{
            .id = .ID("Panel"),
            .layout = .{ .padding = .all(20), .sizing = .{ .w = .fixed(320), .h = .fixed(90) } },
            .background_color = panel,
            .corner_radius = .all(8),
        })({
            clay.text("Hello Clay UI!", .{ .font_size = 28, .color = text_col });
        });
    });
}

fn colorToVec(c: clay.Color) [4]f32 {
    return .{ c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, c[3] / 255.0 };
}

fn boxToRect(box: clay.BoundingBox, clamp: vk.Extent2D) vk.Rect2D {
    const x: i32 = @intFromFloat(@max(box.x, 0));
    const y: i32 = @intFromFloat(@max(box.y, 0));
    return .{
        .offset = .{ .x = x, .y = y },
        .extent = .{
            .width = @min(@as(u32, @intFromFloat(@max(box.width, 0))), clamp.width),
            .height = @min(@as(u32, @intFromFloat(@max(box.height, 0))), clamp.height),
        },
    };
}

fn translate(self: *UI, cmds: []clay.RenderCommand, extent: vk.Extent2D) !void {
    self.verts.clearRetainingCapacity();
    self.indices.clearRetainingCapacity();
    self.groups.clearRetainingCapacity();

    const full_scissor: vk.Rect2D = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent };
    var current_scissor = full_scissor;
    var group_start: u32 = 0;

    const startNewGroup = struct {
        fn call(u: *UI, start: *u32, scissor: vk.Rect2D) !void {
            const idx_now: u32 = @intCast(u.indices.items.len);
            if (idx_now > start.*) {
                try u.groups.append(u.allocator, .{
                    .first_index = start.*,
                    .index_count = idx_now - start.*,
                    .scissor = scissor,
                });
                start.* = idx_now;
            }
        }
    }.call;

    for (cmds) |cmd| {
        switch (cmd.command_type) {
            .rectangle => {
                const d = cmd.render_data.rectangle;
                try self.pushQuad(cmd.bounding_box, .{ 0, 0 }, .{ 1, 1 }, colorToVec(d.background_color), 0);
            },
            .text => {
                try self.pushText(cmd);
            },
            .image => {
                const d = cmd.render_data.image;
                const slot = imageDataToSlot(d.image_data);
                try self.pushQuad(cmd.bounding_box, .{ 0, 0 }, .{ 1, 1 }, colorToVec(d.background_color), slot);
            },
            .border => {
                const d = cmd.render_data.border;
                const col = colorToVec(d.color);
                const r = cmd.bounding_box;
                if (d.width.top > 0) try self.pushRect(r.x, r.y, r.width, @floatFromInt(d.width.top), col);
                if (d.width.bottom > 0) try self.pushRect(r.x, r.y + r.height - @as(f32, @floatFromInt(d.width.bottom)), r.width, @floatFromInt(d.width.bottom), col);
                if (d.width.left > 0) try self.pushRect(r.x, r.y, @floatFromInt(d.width.left), r.height, col);
                if (d.width.right > 0) try self.pushRect(r.x + r.width - @as(f32, @floatFromInt(d.width.right)), r.y, @floatFromInt(d.width.right), r.height, col);
            },
            .scissor_start => {
                try startNewGroup(self, &group_start, current_scissor);
                current_scissor = boxToRect(cmd.bounding_box, extent);
            },
            .scissor_end => {
                try startNewGroup(self, &group_start, current_scissor);
                current_scissor = full_scissor;
            },
            .custom, .none => {},
        }
    }
    try startNewGroup(self, &group_start, current_scissor);
}

fn pushRect(self: *UI, x: f32, y: f32, w: f32, h: f32, col: [4]f32) !void {
    try self.pushQuad(.{ .x = x, .y = y, .width = w, .height = h }, .{ 0, 0 }, .{ 1, 1 }, col, 0);
}

fn pushQuad(self: *UI, box: clay.BoundingBox, uv_min: [2]f32, uv_max: [2]f32, col: [4]f32, tex_id: u32) !void {
    const base: u16 = @intCast(self.verts.items.len);
    const x0 = box.x;
    const y0 = box.y;
    const x1 = box.x + box.width;
    const y1 = box.y + box.height;
    try self.verts.appendSlice(self.allocator, &.{
        .{ .pos = .{ x0, y0 }, .uv = .{ uv_min[0], uv_min[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x1, y0 }, .uv = .{ uv_max[0], uv_min[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x1, y1 }, .uv = .{ uv_max[0], uv_max[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x0, y1 }, .uv = .{ uv_min[0], uv_max[1] }, .col = col, .tex_id = tex_id },
    });
    try self.indices.appendSlice(self.allocator, &.{ base, base + 1, base + 2, base + 2, base + 3, base });
}

fn pushText(self: *UI, cmd: clay.RenderCommand) !void {
    const font = &self.font_manager.font;
    const d = cmd.render_data.text;
    const col = colorToVec(d.text_color);
    const scale = @as(f32, @floatFromInt(d.font_size)) / font.base_size;
    const baseline_y = cmd.bounding_box.y + font.ascent * scale;

    var pen_x = cmd.bounding_box.x;
    const chars = d.string_contents.chars[0..@intCast(d.string_contents.length)];
    for (chars) |c| {
        const g = font.glyph(c) orelse continue;
        if (g.size[0] > 0 and g.size[1] > 0) {
            const gw = g.size[0] * scale;
            const gh = g.size[1] * scale;
            const gx = pen_x + g.bearing[0] * scale; // left bearing
            const gy = baseline_y - g.bearing[1] * scale; // top = baseline - (glyph top above baseline)
            try self.pushQuad(
                .{ .x = gx, .y = gy, .width = gw, .height = gh },
                g.uv_min,
                g.uv_max,
                col,
                font.atlas_slot,
            );
        }
        pen_x += g.advance * scale + @as(f32, @floatFromInt(d.letter_spacing));
    }
}

/// Record the UI draw into `cmd`, compositing onto `engine.draw_image`
/// (already in color_attachment_optimal). Call after drawGeometry, before
/// draw_image is transitioned to transfer_src.
pub fn recordDraw(self: *UI, engine: *Engine, extent: vk.Extent2D) void {
    if (self.groups.items.len == 0) return;

    const frame = engine.getCurrentFrame();
    const cmd = frame.cmd_buf.vk_command_buffer;

    const color_attachment: vk.RenderingAttachmentInfo = .{
        .image_layout = .color_attachment_optimal,
        .image_view = engine.draw_image.view,
        .resolve_mode = .{},
        .resolve_image_view = .null_handle,
        .resolve_image_layout = .undefined,
        .load_op = .load,
        .store_op = .store,
        .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
    };
    const rendering_info: vk.RenderingInfo = .{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment),
        .p_depth_attachment = null,
        .p_stencil_attachment = null,
    };

    engine.ctx.device.cmdBeginRendering(cmd, &rendering_info);
    defer engine.ctx.device.cmdEndRendering(cmd);

    const pipeline = engine.pipelines.get(._2d);
    const layout = engine.pipeline_layouts.get(._2d);

    engine.ctx.device.cmdBindPipeline(cmd, .graphics, pipeline.vk_pipeline);
    engine.ctx.device.cmdBindDescriptorSets(cmd, .graphics, layout, 0, &.{frame.descriptor_set}, null);
    engine.ctx.device.cmdSetViewport(cmd, 0, &.{frame.viewport});
    engine.ctx.device.cmdBindIndexBuffer(cmd, self.index_buffer.vk_buffer, 0, .uint16);

    const pc: Buffers.UIPushConstants = .{
        .screen_size = .{ @floatFromInt(extent.width), @floatFromInt(extent.height) },
        .vb_address = self.vertex_buffer.address.?,
    };
    engine.ctx.device.cmdPushConstants(cmd, layout, .{ .vertex_bit = true }, 0, @sizeOf(Buffers.UIPushConstants), @ptrCast(&pc));

    for (self.groups.items) |group| {
        engine.ctx.device.cmdSetScissor(cmd, 0, &.{group.scissor});
        engine.ctx.device.cmdDrawIndexed(cmd, group.index_count, 1, group.first_index, 0, 0);
    }
}

/// A bindless slot round-trips through Clay's opaque image_data pointer as
/// slot+1 (so slot 0 is distinguishable from a null image_data).
pub fn slotToImageData(slot: u32) ?*anyopaque {
    return @ptrFromInt(@as(usize, slot) + 1);
}
fn imageDataToSlot(ptr: ?*anyopaque) u32 {
    return @intCast(@intFromPtr(ptr orelse return 0) -| 1);
}
