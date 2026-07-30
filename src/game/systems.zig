const std = @import("std");
const log = std.log.scoped(.ecs_systems);
const zm = @import("zmath");
const sdl = @import("sdl3");
const zgui = @import("zgui");

const World = @import("../ecs/world.zig");
const Components = World.Components;
const Schedule = World.Schedule;
const Gamestate = World.Gamestate;
const GameComponents = @import("components.zig");

const Query = World.Ecs.Query;
const QueryF = World.Ecs.QueryF;
const With = World.Ecs.Filter.With;
const ResMut = World.Ecs.ResMut;
const Res = World.Ecs.Res;
const Commands = World.Ecs.Commands;
const EventReader = World.Ecs.EventReader;
const EventWriter = World.Ecs.EventWriter;

const GameUi = @import("ui.zig");

const Resource = @import("../resource_management/resource.zig");
const SerdeCodec = @import("../scene_management/serializer.zig").SerdeCodec;

const Uuid = @import("uuid");
const SceneObjects = @import("../scene_management/objects.zig");

pub const Plugins = struct {
    pub const Game = struct {
        pub fn plugin(world: *World.Ecs.App) !void {
            try world.addResource(GameComponents.MapBoardState{});

            try world.addSystem(Schedule.pre_render, &setupGameUi);
        }
    };
};

fn setupGameUi(
    alloc: World.Ecs.Alloc,
    cmd: Commands,
    ui: ResMut(Components.UIManagerHandle),
    existing: Query(struct { c: *const Components.UiCanvasComponent }),
    window: Res(Components.WindowState),
) !void {
    var it = existing.iter();
    if (it.next() != null) return;

    const canvas = try ui.inner.ptr.createCanvas(.{
        .screen = .{ .width = @intCast(window.inner.width), .height = @intCast(window.inner.height) },
    });

    try canvas.widgets.append(alloc.gpa, GameUi.test_canvas);

    _ = try cmd.spawn(.{
        Components.ID{ .guid = Uuid.v4.new(alloc.io) },
        Components.UiCanvasComponent{ .canvas = canvas },
        Components.TransformComponent{
            .translation = .{ .x = -2, .y = -7, .z = -10 },
            .scale = .{ .x = -2 },
        },
        Components.Visible{ .visible = true },
    });

    const canvas_attached = try ui.inner.ptr.createCanvas(.{
        .world = .{ .width = 500, .height = 384 },
    });

    try canvas_attached.widgets.append(alloc.gpa, GameUi.test_world_canvas);

    _ = try cmd.spawn(.{
        Components.ID{ .guid = Uuid.v4.new(alloc.io) },
        Components.UiCanvasComponent{ .canvas = canvas_attached },
        Components.TransformComponent{
            .translation = .{ .x = 2, .y = 7, .z = 10 },
            .scale = .{ .x = 2, .y = 3, .z = 5 },
        },
        Components.Visible{ .visible = true },
    });
}
