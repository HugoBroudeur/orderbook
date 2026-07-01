const std = @import("std");
const log = std.log.scoped(.scene_editor);
const zgui = @import("zgui");

const ProjectManager = @import("../project/manager.zig");
const Engine = @import("../engine/vulkan/engine.zig");
const SceneManager = @import("../engine/scene_manager.zig");

const SceneEditor = @This();

allocator: std.mem.Allocator,
engine: *Engine,
project_manager: *ProjectManager,

pub fn init(allocator: std.mem.Allocator, engine: *Engine, project_manager: *ProjectManager) SceneEditor {
    return .{
        .allocator = allocator,
        .engine = engine,
        .project_manager = project_manager,
    };
}

pub fn deinit(self: *SceneEditor) void {
    _ = self;
}

pub fn display(self: *SceneEditor) void {
    if (zgui.begin("Debug info", .{})) {
        zgui.bulletText(
            "Average :  {d:.2}  ms/frame ({d:.1}  fps)",
            .{ self.engine.stats.clocks.get(.frame).?.average_ms, self.engine.stats.frame_per_sec },
        );
        zgui.bulletText("Hold left click : use camera", .{});
        zgui.bulletText("D, S, T, R :  move camera", .{});
        zgui.spacing();
    }
    zgui.end();

    zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
    zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

    if (zgui.begin("Scene Editor", .{})) {
        if (zgui.collapsingHeader("Scene data", .{ .default_open = true, .draw_lines_full = true })) {
            _ = zgui.colorPicker4("Ambiant Color", .{
                .col = &self.engine.scene_manager.scene_data.ambient_color,
                .flags = .{ .alpha_bar = true, .picker_hue_wheel = true },
            });
            _ = zgui.colorPicker4("Sunlight Color", .{
                .col = &self.engine.scene_manager.scene_data.sunlight_color,
                .flags = .{ .alpha_bar = true, .picker_hue_wheel = true },
            });
            const sun_direction = self.engine.scene_manager.scene_data.sunlight_direction[0..3];
            if (zgui.dragFloat3("Sunlight Direction", .{ .v = sun_direction, .speed = 0.01 })) {
                self.engine.scene_manager.scene_data.sunlight_direction[0] = sun_direction[0];
                self.engine.scene_manager.scene_data.sunlight_direction[1] = sun_direction[1];
                self.engine.scene_manager.scene_data.sunlight_direction[2] = sun_direction[2];
            }

            var sun_power = self.engine.scene_manager.scene_data.sunlight_direction[3];
            if (zgui.dragFloat("Sunlight Power", .{ .v = &sun_power, .speed = 0.01 })) {
                self.engine.scene_manager.scene_data.sunlight_direction[3] = sun_power;
            }

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
