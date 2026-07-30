const std = @import("std");
const zm = @import("zmath");
const clay = @import("zclay");

const Buffer = @import("../engine/vulkan/buffer.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const UIVertex = @import("../engine/data.zig").UIVertex;

//  |------------------------------|
//  |  Canvas  (owns GPU buffers)  |
//  |   panel  ....  dialog        |   panel/dialog = top-level Widgets
//  |    widget widget             |   widget       = the inside of a clay.UI()
//  |------------------------------|

pub const Widget = union(enum) {
    pub const Element = struct {
        decl: clay.ElementDeclaration = .{},
        children: []const Widget = &.{},
    };

    pub const Text = struct {
        config: clay.TextElementConfig = .{},
        content: []const u8,
    };

    element: Element,
    text: Text,

    pub fn build(self: *const Widget) void {
        switch (self.*) {
            .text => |t| clay.text(t.content, t.config),
            .element => |e| clay.UI()(e.decl)({
                for (e.children) |*child| child.build();
            }),
        }
    }
};

pub const Extent = struct {
    width: u32,
    height: u32,
};

pub const UiCanva = struct {
    pub const CanvasKind = union(enum) {
        screen: Extent,
        world: Extent,
    };

    id: u32,

    widgets: std.ArrayList(Widget) = .empty,

    world_transform: zm.Mat = zm.identity(),
    local_transform: zm.Mat = zm.identity(),

    kind: CanvasKind,
    pub fn init(id: u32, kind: CanvasKind) UiCanva {
        return .{
            .id = id,
            .kind = kind,
        };
    }

    pub fn refreshTransform(self: *UiCanva, parent_matrix: zm.Mat) void {
        self.world_transform = switch (self.kind) {
            .screen => |extent| toScreenCoordinates(@floatFromInt(extent.width), @floatFromInt(extent.height)),
            .world => |extent| zm.mul(toWorldCoordinates(@floatFromInt(extent.width), @floatFromInt(extent.height)), parent_matrix),
        };
    }

    fn toScreenCoordinates(w: f32, h: f32) zm.Mat {
        return .{
            zm.f32x4(2.0 / w, 0, 0, 0),
            zm.f32x4(0, 2.0 / h, 0, 0),
            zm.f32x4(0, 0, 1, 0),
            zm.f32x4(-1, -1, 0, 1),
        };
    }

    fn toWorldCoordinates(w: f32, h: f32) zm.Mat {
        const s = 1 / h;
        return .{
            zm.f32x4(s, 0, 0, 0),
            zm.f32x4(0, -s, 0, 0),
            zm.f32x4(0, 0, 1, 0),
            zm.f32x4(-(w / 2) / h, 0.5, 0, 1),
        };
    }

    pub fn destroy(self: *UiCanva, allocator: std.mem.Allocator) void {
        self.widgets.deinit(allocator);
    }
};
