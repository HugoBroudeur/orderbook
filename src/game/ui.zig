const clay = @import("zclay");
const Ui = @import("../ui/objects.zig");
const Widget = Ui.Widget;

const black: [4]f32 = .{ 235, 235, 245, 255 };
const panel: clay.Color = .{ 40, 44, 62, 255 };
const redish: clay.Color = .{ 232, 44, 62, 255 };

// Data form of the old buildTestLayout(): two text lines in a rounded panel,
// centered on screen. The UiManager walks this tree to emit Clay calls — no
// per-canvas Zig build function. IDs are omitted because ElementId.ID() hashes
// at runtime and can't appear in a comptime const (IDs are only needed for
// interaction/debug, not rendering).
//
// Panels/dialogs would be additional top-level `.element` children here (a
// panel sized to its content, a dialog sized `.grow` to fill the canvas).
pub const test_canvas: Widget = .{
    .element = .{
        .decl = .{
            .layout = .{
                .sizing = .grow,
                .child_alignment = .{ .x = .center, .y = .center },
                .direction = .top_to_bottom,
                .child_gap = 8,
            },
        },
        .children = &.{
            .{ .element = .{
                .decl = .{
                    .layout = .{ .padding = .all(20) },
                    .background_color = panel,
                    .corner_radius = .all(8),
                },
                .children = &.{
                    .{ .text = .{ .content = "Hello from Game ECS !", .config = .{ .font_size = 28, .color = black } } },
                    .{ .text = .{ .content = "Data-driven UI canvas", .config = .{ .font_size = 28, .color = black } } },
                },
            } },
        },
    },
};

pub const test_world_canvas: Widget = .{
    .element = .{
        .decl = .{
            .layout = .{
                .sizing = .grow,
                .child_alignment = .{ .x = .center, .y = .center },
                .direction = .top_to_bottom,
                .child_gap = 8,
            },
        },
        .children = &.{
            .{ .element = .{
                .decl = .{
                    .layout = .{ .padding = .all(20) },
                    .background_color = redish,
                    .corner_radius = .all(8),
                },
                .children = &.{
                    .{ .text = .{ .content = "WORLD UI canvas", .config = .{ .font_size = 28, .color = black } } },
                },
            } },
        },
    },
};
