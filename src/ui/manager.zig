const std = @import("std");
const log = std.log.scoped(.ui);
const zm = @import("zmath");
const vk = @import("vulkan");
const clay = @import("zclay");

const objects = @import("objects.zig");
const UiCanva = objects.UiCanva;
const Widget = objects.Widget;

const Engine = @import("../engine/vulkan/engine.zig");
const Buffers = @import("../engine/graphics/buffers.zig");
const UIVertex = @import("../engine/data.zig").UIVertex;
const ResourceManager = @import("../resource_management/manager.zig");
const Font = @import("../resource_management/font.zig").Font;
const Buffer = @import("../engine/vulkan/buffer.zig");

const UiManager = @This();

const FONT_PATH = "assets/fonts/SNPro/SNPro-Regular.ttf";
const FONT_SIZE: f32 = 18;

const MAX_VERTS: u32 = 65536;
const MAX_INDICES: u32 = 98304;

pub const Offset = struct {
    x: i32,
    y: i32,
};
pub const Extent = struct {
    width: u32,
    height: u32,
};

pub const Scissor = struct {
    offset: Offset,
    extent: Extent,
};

pub const CanvaData = struct {
    pub const DrawGroup = struct {
        first_index: u32,
        index_count: u32,
        scissor: Scissor,
    };

    canvas: *UiCanva,
    vertex_buffer: Buffer,
    index_buffer: Buffer,

    vertex: std.ArrayList(UIVertex) = .empty,
    indices: std.ArrayList(u16) = .empty,
    groups: std.ArrayList(DrawGroup) = .empty,

    // Manage frame state, to know if it needs to be uploaded to GPU
    hash: u64 = 0,

    pub fn destroy(self: *CanvaData, allocator: std.mem.Allocator) void {
        self.index_buffer.destroy();
        self.vertex_buffer.destroy();
        self.vertex.deinit(allocator);
        self.indices.deinit(allocator);
        self.groups.deinit(allocator);
    }
};

engine: *Engine,
font: *Font,

clay_arena: []u8,

canvas: std.AutoHashMap(u32, CanvaData),
queue: std.ArrayList(u32) = .empty,

// internal state
_next_canva_id: u32 = 0,

pub fn init(engine: *Engine, res_manager: *ResourceManager) !UiManager {
    const handle = try res_manager.loadFont(Font.init(
        ResourceManager.makeId(.{ .content = FONT_PATH }),
        "ui_font",
        .{ .file = .{ .path = FONT_PATH, .size = FONT_SIZE } },
    ));

    const font = handle.get().?;

    const clay_arena = try engine.allocator.alignedAlloc(u8, .@"8", clay.minMemorySize());
    const arena: clay.Arena = .init(clay_arena);
    _ = clay.initialize(arena, .{ .w = 100, .h = 100 }, .{});
    clay.setMeasureTextFunction(*Font, font, measureText);

    log.info("[UiManager] initialized (font slot {d})", .{font.atlasSlot()});

    return .{
        .engine = engine,
        .font = font,
        .clay_arena = clay_arena,
        .canvas = .init(engine.allocator),
    };
}

pub fn deinit(self: *UiManager) void {
    const allocator = self.engine.allocator;
    var it = self.canvas.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.destroy(allocator);
        allocator.destroy(entry.value_ptr.canvas);
    }
    self.canvas.deinit();
    self.queue.deinit(allocator);
    allocator.free(self.clay_arena);
}

pub fn createCanvas(self: *UiManager, kind: UiCanva.CanvasKind) !*UiCanva {
    const canvas = try self.engine.allocator.create(UiCanva);
    canvas.* = UiCanva.init(self._next_canva_id, kind);

    const vertex_buffer = try Buffer.create(
        self.engine,
        MAX_VERTS * @sizeOf(UIVertex),
        .{ .shader_device_address_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    const index_buffer = try Buffer.create(
        self.engine,
        MAX_INDICES * @sizeOf(u16),
        .{ .index_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    try self.canvas.put(self._next_canva_id, .{ .canvas = canvas, .index_buffer = index_buffer, .vertex_buffer = vertex_buffer });
    self._next_canva_id += 1;

    return canvas;
}

pub fn resetQueue(self: *UiManager) void {
    self.queue.clearRetainingCapacity();
}

pub fn addToDrawList(self: *UiManager, canva: *UiCanva) !void {
    if (self.canvas.getPtr(canva.id)) |data| {
        try self.queue.append(self.engine.allocator, canva.id);

        const dims: clay.Dimensions = switch (data.canvas.kind) {
            .screen => |extent| .{ .w = @floatFromInt(extent.width), .h = @floatFromInt(extent.height) },
            .world => |extent| .{ .w = @floatFromInt(extent.width), .h = @floatFromInt(extent.height) },
        };
        clay.setLayoutDimensions(dims);

        clay.beginLayout();
        for (data.canvas.widgets.items) |*widget| {
            widget.build();
        }
        const cmds = clay.endLayout();

        try self.processCommands(data, cmds);

        // Dirty-upload: only re-copy to the GPU when the geometry actually changed.
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.sliceAsBytes(data.vertex.items));
        hasher.update(std.mem.sliceAsBytes(data.indices.items));
        const new_hash = hasher.final();

        // only copy to buffer if data has changed
        if (new_hash != data.hash) {
            if (data.vertex.items.len > 0)
                try data.vertex_buffer.copyInto(std.mem.sliceAsBytes(data.vertex.items), 0);
            if (data.indices.items.len > 0)
                try data.index_buffer.copyInto(std.mem.sliceAsBytes(data.indices.items), 0);
            data.hash = new_hash;
        }
    }
}

fn processCommands(self: *UiManager, data: *CanvaData, cmds: []clay.RenderCommand) !void {
    data.vertex.clearRetainingCapacity();
    data.indices.clearRetainingCapacity();
    data.groups.clearRetainingCapacity();

    const canva = data.canvas;

    const clamp: Extent = switch (canva.kind) {
        .screen => |extent| .{ .width = extent.width, .height = extent.height },
        .world => .{ .width = self.engine.swapchain.extent.width, .height = self.engine.swapchain.extent.height },
    };
    const full_scissor: Scissor = .{ .offset = .{ .x = 0, .y = 0 }, .extent = clamp };
    var current_scissor = full_scissor;
    var group_start: u32 = 0;

    for (cmds) |cmd| {
        const bounding_box = cmd.bounding_box;

        switch (cmd.command_type) {
            .rectangle => {
                const config = cmd.render_data.rectangle;
                try self.pushQuad(data, bounding_box, .{ 0, 0 }, .{ 1, 1 }, config.background_color, 0);
            },
            .text => {
                const font = self.font;
                const config = cmd.render_data.text;
                const scale = @as(f32, @floatFromInt(config.font_size)) / font.base_size;

                var pen_x = bounding_box.x;
                const chars = config.string_contents.chars[0..@intCast(config.string_contents.length)];
                for (chars) |c| {
                    const g = font.glyph(c) orelse continue;
                    // if (g.size[0] > 0 and g.size[1] > 0) {
                    try self.pushQuad(
                        data,
                        .{ .x = pen_x, .y = bounding_box.y, .width = g.size[0] * scale, .height = g.size[1] * scale },
                        g.uv_min,
                        g.uv_max,
                        config.text_color,
                        font.atlasSlot(),
                    );
                    // }
                    pen_x += g.advance * scale + @as(f32, @floatFromInt(config.letter_spacing));
                }
            },

            .image => {
                const config = cmd.render_data.image;
                const slot: u32 = @intCast(@intFromPtr(config.image_data) -| 1);
                try self.pushQuad(data, bounding_box, .{ 0, 0 }, .{ 1, 1 }, config.background_color, slot);
            },
            .border => {
                const config = cmd.render_data.border;
                const col = config.color;
                if (config.width.top > 0) try self.pushRect(data, bounding_box.x, bounding_box.y, bounding_box.width, @floatFromInt(config.width.top), col);
                if (config.width.bottom > 0) try self.pushRect(data, bounding_box.x, bounding_box.y + bounding_box.height - @as(f32, @floatFromInt(config.width.bottom)), bounding_box.width, @floatFromInt(config.width.bottom), col);
                if (config.width.left > 0) try self.pushRect(data, bounding_box.x, bounding_box.y, @floatFromInt(config.width.left), bounding_box.height, col);
                if (config.width.right > 0) try self.pushRect(data, bounding_box.x + bounding_box.width - @as(f32, @floatFromInt(config.width.right)), bounding_box.y, @floatFromInt(config.width.right), bounding_box.height, col);
            },
            .scissor_start => {
                try self.addGroup(data, &group_start, current_scissor);

                const x: i32 = @intFromFloat(@max(bounding_box.x, 0));
                const y: i32 = @intFromFloat(@max(bounding_box.y, 0));

                current_scissor = .{
                    .offset = .{ .x = x, .y = y },
                    .extent = .{
                        .width = @min(@as(u32, @intFromFloat(@max(bounding_box.width, 0))), clamp.width),
                        .height = @min(@as(u32, @intFromFloat(@max(bounding_box.height, 0))), clamp.height),
                    },
                };
            },
            .scissor_end => {
                try self.addGroup(data, &group_start, current_scissor);
                current_scissor = full_scissor;
            },
            .custom, .none => {},
        }
    }
    try self.addGroup(data, &group_start, current_scissor);
}

fn pushRect(self: *UiManager, data: *CanvaData, x: f32, y: f32, w: f32, h: f32, clayColor: clay.Color) !void {
    try self.pushQuad(data, .{ .x = x, .y = y, .width = w, .height = h }, .{ 0, 0 }, .{ 1, 1 }, clayColor, 0);
}

fn pushQuad(self: *UiManager, data: *CanvaData, box: clay.BoundingBox, uv_min: [2]f32, uv_max: [2]f32, clayColor: clay.Color, tex_id: u32) !void {
    const alloc = self.engine.allocator;
    const base: u16 = @intCast(data.vertex.items.len);
    const x0 = box.x;
    const y0 = box.y;
    const x1 = box.x + box.width;
    const y1 = box.y + box.height;
    const col: [4]f32 = .{ clayColor[0] / 255.0, clayColor[1] / 255.0, clayColor[2] / 255.0, clayColor[3] / 255.0 };
    try data.vertex.appendSlice(alloc, &.{
        .{ .pos = .{ x0, y0 }, .uv = .{ uv_min[0], uv_min[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x1, y0 }, .uv = .{ uv_max[0], uv_min[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x1, y1 }, .uv = .{ uv_max[0], uv_max[1] }, .col = col, .tex_id = tex_id },
        .{ .pos = .{ x0, y1 }, .uv = .{ uv_min[0], uv_max[1] }, .col = col, .tex_id = tex_id },
    });
    try data.indices.appendSlice(alloc, &.{ base, base + 1, base + 2, base + 2, base + 3, base });
}

fn addGroup(self: *UiManager, data: *CanvaData, start: *u32, scissor: Scissor) !void {
    const idx_now: u32 = @intCast(data.indices.items.len);
    if (idx_now > start.*) {
        try data.groups.append(self.engine.allocator, .{
            .first_index = start.*,
            .index_count = idx_now - start.*,
            .scissor = scissor,
        });
        start.* = idx_now;
    }
}

/// Clay text-measurement callback; `ctx` is the manager's Font resource, passed
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
