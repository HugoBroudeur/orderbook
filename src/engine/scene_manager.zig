const std = @import("std");
const Camera = @import("camera.zig");
const Commands = @import("command.zig");
const SceneData = @import("command.zig").SceneData;
const UniformData = @import("../engine/command.zig").UniformData;
const SceneA = @import("graphics/scene.zig");
const EcsManager = @import("../game/ecs_manager.zig");
const Ecs = @import("../game/ecs/ecs.zig");
const zm = @import("zmath");
const Color = @import("../primitive.zig").Color;
const LoadedGLTF = @import("graphics/scene.zig").LoadedGLTF;
const AssetManager = @import("asset_manager.zig").AssetManager;
const Engine = @import("vulkan/engine.zig");

const SceneManager = @This();

pub const Scene = struct {
    name: []const u8,
};

io: std.Io,
camera: Camera.PerspectiveCamera,
current_scene: Scene,
draw_queue: *Commands.DrawQueue,

random: std.Random,

pub fn init(draw_queue: *Commands.DrawQueue, io: std.Io) SceneManager {
    const clock: std.Io.Clock = .cpu_thread;
    const timestamp = clock.now(io).toMilliseconds();
    // Use current timestamp as seed
    var prng = std.Random.DefaultPrng.init(@intCast(timestamp));

    // const roll = rand.intRangeAtMost(u32, 1, 6); // Dice roll: 1-6
    return .{
        .io = io,
        .camera = .{ .name = "2D Orthographic Camera" },
        .current_scene = .{ .name = "Main Loop" },
        .draw_queue = draw_queue,
        .random = prng.random(),
    };
}

pub fn deinit(self: *SceneManager) void {
    _ = self;
}

pub fn render(self: *SceneManager, ecs_manager: *const EcsManager, engine: *Engine) void {
    Ecs.logger.info("[SceneManager.render] Camera: {s}", .{self.camera.name});
    // const draw_data = ecs_manager.get_singleton(Ecs.components.Graphics.DrawData);

    self.beginScene(engine, ecs_manager);

    // Draw the Imgui UI
    // self.draw_queue.push(.{ .imgui = .{ .data = draw_data.ui } });
    // self.draw_queue.push(.{ .set_camera = .{
    //     .view = camera.view_matrix,
    //     .proj = camera.proj_matrix,
    //     .frustum = camera.frustum,
    // } });
    // command_queue.push(.{.draw_mesh});

    // 2D test quads commented out — were blending over the 3D scene causing a colour tint

    self.endScene();
}

pub fn beginScene(self: *SceneManager, engine: *Engine, ecs_manager: *const EcsManager) void {
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

        const width: usize = engine.ctx.window.getWidth();
        const heigth: usize = engine.ctx.window.getHeight();

        camera.setViewport(.{
            .x = 0,
            .y = 0,
            .width = @intCast(width),
            .heigth = @intCast(heigth),
        });

        var scene_data: SceneData = .{};

        scene_data.view = camera.getViewMatrix();
        scene_data.proj = camera.getProjectionMatrix();
        scene_data.view_proj = camera.getViewProjMatrix();

        scene_data.ambient_color = .{ .r = 1, .g = 1, .b = 1, .a = 0.1 };
        scene_data.sunlight_color = Color.White;
        scene_data.sunlight_direction = .{ 0, 1, 0.5, 1 };

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
