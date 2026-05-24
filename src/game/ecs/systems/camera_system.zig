const std = @import("std");
const log = std.log.scoped(.camera_system);
const zecs = @import("zecs");
// const log = @import("../../debug/log.zig").ecs;
const System = @import("system.zig");
const Event = @import("../../../events/event.zig");
const EcsManager = @import("../../ecs_manager.zig");
const Ecs = @import("../ecs.zig");
const Camera = @import("../../../renderer/camera.zig");

const CameraSystem = @This();

camera: Camera.PerspectiveCamera = undefined,
ecs: *EcsManager,

const MOUSE_SENSITIVITY = 200;
const SPEED = 0.05;

pub fn init(ecs: *EcsManager) CameraSystem {
    return .{ .ecs = ecs };
}

pub fn interface(self: *CameraSystem) System {
    return System.init(self);
}

pub fn setup(self: *CameraSystem) void {
    const es = self.ecs.createEntity();
    // Pull camera back along +Z so meshes at the world origin are in front of it.
    self.ecs.addComponent(es, Camera.PerspectiveCamera, .{
        .near = 0.1,
        .far = 10000,
        .fov = 70,
        .pos = .{ 0, 0, 5, 1 },
    });
    self.ecs.addComponent(es, Ecs.components.Velocity, .{});
    self.ecs.addComponent(es, Ecs.components.Rotation, .{});

    self.ecs.flush_cmd_buf();
}

pub fn update(self: *CameraSystem) void {
    var iter = self.ecs.entities.iterator(struct {
        camera: *Camera.PerspectiveCamera,
        velocity: *Ecs.components.Velocity,
        rotation: *Ecs.components.Rotation,
    });

    const dt = self.ecs.getDeltaTime();

    while (iter.next(&self.ecs.entities)) |vw| {
        const camera = vw.camera;
        camera.setLookAt(vw.rotation.yaw, vw.rotation.pitch);
        camera.pos = .{
            camera.pos[0] + @as(f32, @floatFromInt(dt)) * vw.velocity.x,
            camera.pos[1] + @as(f32, @floatFromInt(dt)) * vw.velocity.y,
            camera.pos[2] + @as(f32, @floatFromInt(dt)) * vw.velocity.z,
            camera.pos[3],
        };
    }
}

pub fn process(self: *CameraSystem, event: Event) void {
    var iter = self.ecs.entities.iterator(struct {
        camera: *Camera.PerspectiveCamera,
        velocity: *Ecs.components.Velocity,
        rotation: *Ecs.components.Rotation,
    });

    while (iter.next(&self.ecs.entities)) |vw| {
        switch (event.ptr) {
            .key_down => {
                // log.info("Key Pressed {}", .{event.ptr.key_down.key.?});

                switch (event.ptr.key_down.key.?) {
                    .d => vw.velocity.z = -SPEED,
                    .t => vw.velocity.z = SPEED,
                    .r => vw.velocity.x = -SPEED,
                    .s => vw.velocity.x = SPEED,
                    else => {},
                }
            },
            .key_up => {
                // log.info("Key Pressed {}", .{event.ptr.key_down.key.?});

                switch (event.ptr.key_up.key.?) {
                    .d => vw.velocity.z = 0,
                    .t => vw.velocity.z = 0,
                    .r => vw.velocity.x = 0,
                    .s => vw.velocity.x = 0,
                    else => {},
                }
            },
            .mouse_motion => {
                vw.rotation.yaw += event.ptr.mouse_motion.x_rel / MOUSE_SENSITIVITY;
                vw.rotation.pitch += event.ptr.mouse_motion.y_rel / MOUSE_SENSITIVITY;
            },
            .mouse_wheel => {
                vw.camera.fov += event.ptr.mouse_wheel.scroll_y;
            },
            else => {},
        }
    }
}

pub fn deinit(self: *CameraSystem) void {
    _ = self;
}
