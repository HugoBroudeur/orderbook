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

random: std.Random,

pub fn init(draw_queue: *Commands.DrawQueue) SceneManager {
    // Use current timestamp as seed
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));

    // const roll = rand.intRangeAtMost(u32, 1, 6); // Dice roll: 1-6
    return .{
        .camera = .{ .name = "2D Orthographic Camera" },
        .current_scene = .{ .name = "Main Loop" },
        .draw_queue = draw_queue,
        .random = prng.random(),
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

    for (0..100) |i| {
        const r = self.random.float(f32) * 2 - 1; // generate [-1, 1]
        const offset = zm.clamp(1 + r, -1, 1);
        _ = i;
        self.draw_queue.push(.{ .quad_fill = .{
            .p1 = .{ .x = r, .y = offset },
            .p2 = .{ .x = offset, .y = offset },
            .p3 = .{ .x = offset, .y = r },
            .p4 = .{ .x = r, .y = r },
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
