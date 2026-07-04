const std = @import("std");
const zm = @import("zmath");
const log = std.log.scoped(.camera_system);
const zecs = @import("zecs");
// const log = @import("../../debug/log.zig").ecs;
const System = @import("system.zig");
const Event = @import("../../../events/event.zig");
const EcsManager = @import("../../ecs_manager.zig");
const Ecs = @import("../ecs.zig");
// const Camera = @import("../../../engine/camera.zig");

const CameraSystem = @This();

// camera: Camera = undefined,
// ecs: *EcsManager,
//
// const MOUSE_SENSITIVITY = 200;
// const SPEED = 0.05;
//
// pub fn init(ecs: *EcsManager) CameraSystem {
//     return .{ .ecs = ecs };
// }
//
// pub fn interface(self: *CameraSystem) System {
//     return System.init(self);
// }
//
// pub fn setup(self: *CameraSystem) void {
//     const es = self.ecs.createEntity();
//     // Pull camera back along +Z so meshes at the world origin are in front of it.
//     self.ecs.addComponent(es, Camera, .{
//         .kind = .perspective,
//         .near = 0.1,
//         .far = 10000,
//         .fov = 70,
//         .pos = .{ 0, 0, 5, 1 },
//     });
//     self.ecs.addComponent(es, Ecs.components.Velocity, .{});
//     self.ecs.addComponent(es, Ecs.components.Rotation, .{});
//
//     self.ecs.flush_cmd_buf();
// }
//
// pub fn update(self: *CameraSystem) void {
//     var iter = self.ecs.entities.iterator(struct {
//         camera: *Camera,
//         velocity: *Ecs.components.Velocity,
//         rotation: *Ecs.components.Rotation,
//     });
//
//     const dt = self.ecs.getDeltaTime();
//
//     while (iter.next(&self.ecs.entities)) |vw| {
//         const camera = vw.camera;
//         camera.setLookAt(vw.rotation.yaw, vw.rotation.pitch);
//
//         const speed = @as(f32, @floatFromInt(dt));
//         const rot = zm.matFromQuat(camera.look_at);
//
//         const forward = zm.normalize3(zm.mul(zm.f32x4(0, 0, -1, 0), rot));
//         const right = zm.normalize3(zm.mul(zm.f32x4(1, 0, 0, 0), rot));
//         const up = zm.f32x4(0, 1, 0, 0);
//
//         camera.pos += forward * zm.f32x4s(speed * vw.velocity.z);
//         camera.pos += right * zm.f32x4s(speed * vw.velocity.x);
//         camera.pos += up * zm.f32x4s(speed * vw.velocity.y);
//         camera.pos[3] = 1;
//     }
// }
//
// pub fn process(self: *CameraSystem, event: Event) bool {
//     var iter = self.ecs.entities.iterator(struct {
//         camera: *Camera,
//         velocity: *Ecs.components.Velocity,
//         rotation: *Ecs.components.Rotation,
//     });
//
//     while (iter.next(&self.ecs.entities)) |vw| {
//         switch (event.ptr) {
//             .key_down => {
//                 // log.info("Key Pressed {}", .{event.ptr.key_down.key.?});
//
//                 switch (event.ptr.key_down.key.?) {
//                     .d => vw.velocity.z = SPEED,
//                     .t => vw.velocity.z = -SPEED,
//                     .r => vw.velocity.x = -SPEED,
//                     .s => vw.velocity.x = SPEED,
//                     .space => vw.velocity.y = SPEED,
//                     .left_shift => vw.velocity.y = -SPEED,
//                     else => {},
//                 }
//             },
//             .key_up => {
//                 // log.info("Key Pressed {}", .{event.ptr.key_down.key.?});
//
//                 switch (event.ptr.key_up.key.?) {
//                     .d => vw.velocity.z = 0,
//                     .t => vw.velocity.z = 0,
//                     .r => vw.velocity.x = 0,
//                     .s => vw.velocity.x = 0,
//                     .space => vw.velocity.y = 0,
//                     .left_shift => vw.velocity.y = 0,
//
//                     else => {},
//                 }
//             },
//             .mouse_motion => {
//                 if (!self.ecs.get_singleton(Ecs.components.MouseState).locked) break;
//                 vw.rotation.yaw += event.ptr.mouse_motion.x_rel / MOUSE_SENSITIVITY;
//                 const max_pitch = std.math.pi / 2.0 - 0.01;
//                 vw.rotation.pitch = std.math.clamp(
//                     vw.rotation.pitch - event.ptr.mouse_motion.y_rel / MOUSE_SENSITIVITY,
//                     -max_pitch,
//                     max_pitch,
//                 );
//             },
//             .mouse_wheel => {
//                 vw.camera.setFov(vw.camera.fov + event.ptr.mouse_wheel.scroll_y);
//             },
//             else => {
//                 return false;
//             },
//         }
//     }
//     return false;
// }
//
// pub fn deinit(self: *CameraSystem) void {
//     _ = self;
// }
