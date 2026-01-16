const std = @import("std");
const Camera = @import("../renderer/camera.zig");
const Commands = @import("../renderer/command.zig");
const EcsManager = @import("ecs_manager.zig");
const Ecs = @import("ecs/ecs.zig");
const zm = @import("zmath");

const SceneManager = @This();

pub const Scene = struct {
    name: []const u8,
};

camera: Camera.Camera(.orthographic),
current_scene: Scene,
draw_queue: *Commands.DrawQueue,

pub fn init(draw_queue: *Commands.DrawQueue) SceneManager {
    return .{
        .camera = .{ .name = "2D Orthographic Camera" },
        .current_scene = .{ .name = "Main Loop" },
        .draw_queue = draw_queue,
    };
}

pub fn deinit(self: *SceneManager) void {
    _ = self;
}

pub fn render(self: *SceneManager, ecs_manager: *EcsManager) void {
    Ecs.logger.info("[SceneManager.render] Camera: {s}", .{self.camera.name});
    const draw_data = ecs_manager.get_singleton(Ecs.components.Graphics.DrawData);

    self.beginScene();

    // Draw the Imgui UI
    self.draw_queue.push(.{ .imgui = .{ .data = draw_data.ui } });

    // Send Camera

    // Draw Rect
    self.draw_queue.push(.{ .quad = .{
        .p1 = .{ .x = -1, .y = 0 },
        .p2 = .{ .x = 0, .y = 0 },
        .p3 = .{ .x = 0, .y = -1 },
        .p4 = .{ .x = -1, .y = -1 },
        .color = .Red,
    } });

    for (0..2_000) |i| {
        self.draw_queue.push(.{ .quad_fill = .{
            .p1 = .{ .x = 0, .y = zm.clamp((1 * (1 - @as(f32, @floatFromInt(i)) * 0.01)), -1, 1) },
            .p2 = .{ .x = 1, .y = 1 },
            .p3 = .{ .x = 1, .y = 0 },
            .p4 = .{ .x = 0, .y = 0 },
            .color1 = .Red,
            .color2 = .Yellow,
            .color3 = .Teal,
            .color4 = .Blue,
        } });
    }

    self.endScene();
}

pub fn beginScene(self: *SceneManager) void {
    //TODO
    _ = self;
    // std.log.debug("[Renderer2D.beginScene] Camera: {s}", .{self.camera.name});

    // self.data.texture_shader.bind();
    // self.data.texture_shader.setMat4('u_viewProjection', camera.GetViewProjectionMatrix());
    // self.data.batcher.begin();
}

pub fn endScene(self: *SceneManager) void {
    //TODO
    // std.log.debug("[Renderer2D.endScene]", .{});
    self.draw_queue.submit();
}
