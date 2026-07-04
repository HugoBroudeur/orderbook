const std = @import("std");
const log = std.log.scoped(.scene_editor);
const zgui = @import("zgui");

const ProjectManager = @import("../project/manager.zig");
const SceneManager = @import("../engine/scene_manager.zig");
const World = @import("../ecs/world.zig");

const SceneEditor = @This();

allocator: std.mem.Allocator,
project_manager: *ProjectManager,
world: *World.Ecs.App,

pub fn init(allocator: std.mem.Allocator, project_manager: *ProjectManager, world: *World.Ecs.App) SceneEditor {
    return .{
        .allocator = allocator,
        .project_manager = project_manager,
        .world = world,
    };
}

pub fn deinit(self: *SceneEditor) void {
    _ = self;
}

pub fn display(self: *SceneEditor) void {
    const stats = self.world.getResource(World.Components.Stats) catch null;
    if (zgui.begin("Debug info", .{})) {
        zgui.bulletText(
            "Average :  {d:.2}  ms/frame ({d:.1}  fps)",
            .{ stats.?.clocks.get(.frame).?.average_ms, stats.?.frame_per_sec },
        );
        zgui.bulletText("Hold left click : use camera", .{});
        zgui.bulletText("D, S, T, R :  move camera", .{});
        zgui.spacing();
    }
    zgui.end();

    zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
    zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

    if (zgui.begin("Scene Editor", .{})) {
        const lights = self.world.getResource(World.Components.Lights) catch null;
        if (zgui.collapsingHeader("Scene data", .{ .default_open = true, .draw_lines_full = true })) {
            _ = zgui.colorPicker4("Ambiant Color", .{
                .col = &lights.?.ambient_color,
                .flags = .{ .alpha_bar = true, .picker_hue_wheel = true },
            });
            _ = zgui.colorPicker4("Sunlight Color", .{
                .col = &lights.?.sunlight_color,
                .flags = .{ .alpha_bar = true, .picker_hue_wheel = true },
            });
            const sun_direction = lights.?.sunlight_direction[0..3];
            if (zgui.dragFloat3("Sunlight Direction", .{ .v = sun_direction, .speed = 0.01 })) {
                if (null != lights) {
                    lights.?.sunlight_direction[0] = sun_direction[0];
                    lights.?.sunlight_direction[1] = sun_direction[1];
                    lights.?.sunlight_direction[2] = sun_direction[2];
                }
            }

            if (zgui.dragFloat("Sunlight Power", .{ .v = &lights.?.sunlight_direction[3], .speed = 0.01 })) {}

            // zgui.colorPicker4(label: [:0]const u8, args: ColorPicker3)
            // zgui.bulletText("Hold left click : use camera", .{self.scene_manager.scene_data.ambient_color});
            if (zgui.button("Press me!", .{ .w = 200.0 })) {
                std.debug.print("Button pressed\n", .{});
            }
        }
    }
    zgui.end();

    if (zgui.begin("Project Manager", .{})) {
        zgui.bulletText("Current loaded project: {s}", .{self.project_manager.project_name});
        if (zgui.button("Save", .{ .w = 200.0 })) {
            self.project_manager.save() catch |err| {
                log.err("Can't save project. Reason: {}", .{err});
            };
        }
        if (zgui.button("Open", .{ .w = 200.0 })) {
            self.project_manager.open(self.project_manager.project_name) catch |err| {
                log.err("Can't open project {s}. Reason: {}", .{ self.project_manager.project_name, err });
            };
        }
    }
    zgui.end();
}
