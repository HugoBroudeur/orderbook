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
const ResourceManager = @import("../../resource_management/manager.zig");
const Font = @import("../../resource_management/font.zig").Font;

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

engine: *Engine = undefined,
/// Ref-counted Font resource from the manager's pool — heap-allocated and
/// pointer-stable, so Clay can hold it as measure-text context. The pool
/// owns the ref; it unloads at ResourceManager.deinit (before Engine.deinit
/// in RenderLayer), so UI.deinit must not touch it.
font: *Font = undefined,

clay_arena: []u8 = &.{},
initialized: bool = false,

// GPU buffers (single, shared across frames — fine while UI content is static;
// make per-frame or ring-buffered before driving dynamic UI).
vertex_buffer: Buffer = undefined,
index_buffer: Buffer = undefined,

// CPU-side accumulation, rebuilt every frame.
verts: std.ArrayList(UIVertex) = .empty,
indices: std.ArrayList(u16) = .empty,
groups: std.ArrayList(ScissorGroup) = .empty,

// Text submitted for the current frame (e.g. by the ECS drawUIText system),
// consumed and cleared by buildFrame. `text_bytes` owns the string copies;
// items store offsets, not slices, because the backing array can realloc
// between submits.
submitted: std.ArrayList(SubmittedText) = .empty,
text_bytes: std.ArrayList(u8) = .empty,

pub const TextOptions = struct {
    font_size: u16 = 28,
    /// RGBA, 0-255 (Clay's color convention).
    color: [4]f32 = .{ 235, 235, 245, 255 },
};

const SubmittedText = struct {
    start: usize,
    len: usize,
    opts: TextOptions,
};

/// Queue one line of text for this frame's UI. The bytes are copied, so the
/// caller's buffer only needs to live until this call returns.
pub fn submitText(self: *UI, text: []const u8, opts: TextOptions) !void {
    const start = self.text_bytes.items.len;
    try self.text_bytes.appendSlice(self.engine.allocator, text);
    try self.submitted.append(self.engine.allocator, .{ .start = start, .len = text.len, .opts = opts });
}

/// In-place init (`self` must be at its final address — Clay keeps pointers).
/// Must run after the resource manager has seeded the basic textures, so the
/// font atlas Texture registers after `white` (which must keep bindless
/// slot 0); loading the Font through the manager makes that ordering explicit.
pub fn init(self: *UI, engine: *Engine, res_manager: *ResourceManager) !void {
    self.engine = engine;

    const handle = try res_manager.loadFont(Font.init(
        ResourceManager.makeId(.{ .content = FONT_PATH }),
        "ui_font",
        .{ .file = .{ .path = FONT_PATH, .size = FONT_SIZE } },
    ));
    self.font = handle.get().?;

    self.clay_arena = try engine.allocator.alignedAlloc(u8, .@"8", clay.minMemorySize());
    const arena: clay.Arena = .init(self.clay_arena);
    _ = clay.initialize(arena, .{ .w = 100, .h = 100 }, .{});
    clay.setMeasureTextFunction(*Font, self.font, measureText);

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
    log.info("[UI] initialized (font slot {d})", .{self.font.atlasSlot()});
}

pub fn deinit(self: *UI) void {
    if (!self.initialized) return;
    self.vertex_buffer.destroy();
    self.index_buffer.destroy();
    self.engine.allocator.free(self.clay_arena);
    self.verts.deinit(self.engine.allocator);
    self.indices.deinit(self.engine.allocator);
    self.groups.deinit(self.engine.allocator);
    self.submitted.deinit(self.engine.allocator);
    self.text_bytes.deinit(self.engine.allocator);
}

/// Clay text-measurement callback; `ctx` is the UI's Font resource, passed
/// via clay.setMeasureTextFunction(*Font, font, measureText).
fn measureText(text: []const u8, config: *clay.TextElementConfig, ctx: *Font) clay.Dimensions {
    const scale = @as(f32, @floatFromInt(config.font_size)) / ctx.base_size;

    var width: f32 = 0;
    for (text) |c| {
        const g = ctx.glyph(c) orelse continue;
        width += g.advance * scale + @as(f32, @floatFromInt(config.letter_spacing));
    }
    return .{ .w = width, .h = @floatFromInt(config.font_size) };
}

/// Build this frame's UI layout, translate it to geometry, upload it.
/// `extent` is the target surface size in pixels.
pub fn buildFrame(self: *UI, extent: vk.Extent2D) !void {
    if (!self.initialized) return;
    clay.setLayoutDimensions(.{ .w = @floatFromInt(extent.width), .h = @floatFromInt(extent.height) });

    clay.beginLayout();
    self.buildLayout();
    const cmds = clay.endLayout();
    // Consumed: translate() below reads the command array (which references
    // text_bytes) before anything can overwrite it next frame.
    defer self.submitted.clearRetainingCapacity();
    defer self.text_bytes.clearRetainingCapacity();

    try self.drainCommands(cmds, extent);

    if (self.verts.items.len > 0)
        try self.vertex_buffer.copyInto(std.mem.sliceAsBytes(self.verts.items), 0);
    if (self.indices.items.len > 0)
        try self.index_buffer.copyInto(std.mem.sliceAsBytes(self.indices.items), 0);
}

/// One rounded panel per submitted text line, stacked in the screen center
/// (centered so the editor's docked panels can't sit on top of it).
fn buildLayout(self: *UI) void {
    const panel: clay.Color = .{ 40, 44, 62, 255 };

    clay.UI()(.{
        .id = .ID("Root"),
        .layout = .{
            .sizing = .grow,
            .child_alignment = .{ .x = .center, .y = .center },
            .direction = .top_to_bottom,
            .child_gap = 8,
        },
    })({
        for (self.submitted.items, 0..) |item, i| {
            clay.UI()(.{
                .id = .IDI("TextPanel", @intCast(i)),
                .layout = .{ .padding = .all(20) },
                .background_color = panel,
                .corner_radius = .all(8),
            })({
                clay.text(
                    self.text_bytes.items[item.start..][0..item.len],
                    .{ .font_size = item.opts.font_size, .color = item.opts.color },
                );
            });
        }
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

fn drainCommands(self: *UI, cmds: []clay.RenderCommand, extent: vk.Extent2D) !void {
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
                try u.groups.append(u.engine.allocator, .{
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
    try self.verts.appendSlice(self.engine.allocator, &.{
        .{ .pos = .{ x0, y0 }, .uv = .{ uv_min[0], uv_min[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x1, y0 }, .uv = .{ uv_max[0], uv_min[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x1, y1 }, .uv = .{ uv_max[0], uv_max[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x0, y1 }, .uv = .{ uv_min[0], uv_max[1] }, .col = col, .tex_id = tex_id },
    });
    try self.indices.appendSlice(self.engine.allocator, &.{ base, base + 1, base + 2, base + 2, base + 3, base });
}

fn pushText(self: *UI, cmd: clay.RenderCommand) !void {
    const font = self.font;
    const d = cmd.render_data.text;
    const col = colorToVec(d.text_color);
    const scale = @as(f32, @floatFromInt(d.font_size)) / font.base_size;

    var pen_x = cmd.bounding_box.x;
    const chars = d.string_contents.chars[0..@intCast(d.string_contents.length)];
    for (chars) |c| {
        const g = font.glyph(c) orelse continue;
        if (g.size[0] > 0 and g.size[1] > 0) {
            // SDL_ttf's renderGlyphBlended bakes both bearings into the cell:
            // the surface is full line height with the glyph pre-positioned
            // (the atlas rows share a baseline). Applying the metrics bearing
            // here again would double-offset — place the cell at the pen/line
            // origin as-is.
            try self.pushQuad(
                .{ .x = pen_x, .y = cmd.bounding_box.y, .width = g.size[0] * scale, .height = g.size[1] * scale },
                g.uv_min,
                g.uv_max,
                col,
                font.atlasSlot(),
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
