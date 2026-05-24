const std = @import("std");
const Camera = @import("../renderer/camera.zig");
const Commands = @import("../renderer/command.zig");
const SceneData = @import("../renderer/command.zig").SceneData;
const UniformData = @import("../renderer/command.zig").UniformData;
const EcsManager = @import("ecs_manager.zig");
const Ecs = @import("ecs/ecs.zig");
const zm = @import("zmath");
const Color = @import("../primitive.zig").Color;
const GraphicsContext = @import("../core/graphics_context.zig");

const SceneManager = @This();

pub const Scene = struct {
    name: []const u8,
};

camera: Camera.PerspectiveCamera,
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

pub fn render(self: *SceneManager, ecs_manager: *const EcsManager, ctx: *const GraphicsContext) void {
    Ecs.logger.info("[SceneManager.render] Camera: {s}", .{self.camera.name});
    // const draw_data = ecs_manager.get_singleton(Ecs.components.Graphics.DrawData);

    self.beginScene(ctx, ecs_manager);

    // Draw the Imgui UI
    // self.draw_queue.push(.{ .imgui = .{ .data = draw_data.ui } });
    // self.draw_queue.push(.{ .set_camera = .{
    //     .view = camera.view_matrix,
    //     .proj = camera.proj_matrix,
    //     .frustum = camera.frustum,
    // } });
    // command_queue.push(.{.draw_mesh});

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

pub fn beginScene(self: *SceneManager, ctx: *const GraphicsContext, ecs_manager: *const EcsManager) void {
    // _ = self;
    // std.log.debug("[Renderer2D.beginScene] Camera: {s}", .{self.camera.name});

    // self.data.texture_shader.bind();
    // self.data.texture_shader.setMat4('u_viewProjection', camera.GetViewProjectionMatrix());
    // self.data.batcher.begin();

    var iter = ecs_manager.entities.iterator(struct {
        camera: *Camera.PerspectiveCamera,
    });

    while (iter.next(&ecs_manager.entities)) |vw| {
        const camera = vw.camera;

        const width: usize = ctx.window.getWidth();
        const heigth: usize = ctx.window.getHeight();

        camera.setViewport(.{
            .x = 0,
            .y = 0,
            .width = @intCast(width),
            .heigth = @intCast(heigth),
        });

        var scene_data: SceneData = .{};

        // scene_data.view = zm.translation(0, 0, -5);
        scene_data.view = camera.getViewMatrix();

        scene_data.proj = camera.getProjectionMatrix();
        // invert the Y direction on projection matrix so that we are more similar
        // to opengl and gltf axis
        scene_data.proj[1][1] *= -1;

        // scene_data.view_proj = zm.mul(scene_data.view, scene_data.proj);
        scene_data.view_proj = camera.getViewProjMatrix();
        // Send Camera
        self.draw_queue.setSceneData(scene_data);
        break;
    }
}

pub fn endScene(self: *SceneManager) void {
    //TODO
    // std.log.debug("[Renderer2D.endScene]", .{});
    self.draw_queue.submit();
}

pub fn initUniform() UniformData {
    // const width: usize = self.ctx.window.getWidth();
    // const heigth: usize = self.ctx.window.getHeight();
    const width: usize = 1080;
    const heigth: usize = 800;
    const fov: f32 = 40;
    const near: f32 = 0.0001;
    const far: f32 = 1000;

    return .{
        .transform = .{
            .scale = .{ 0.5, 0.5 },
            .translate = .{ 0, 0 },
        },
        .mvp = .{
            .proj_matrix = zm.perspectiveFovRh(zm.modAngle(fov), @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(heigth)), near, far),
            // .proj_matrix = zm.identity(),
            .view_matrix = zm.identity(),
        },
        .time = .{
            .time = 0,
        },
    };
}
