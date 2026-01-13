const std = @import("std");

pub const CameraType = enum { orthographic, perspective };

pub fn Camera(comptime T: CameraType) type {
    return struct {
        name: []const u8 = @tagName(T),
    };
}

// pub const Camera = struct {
//     primary: bool = false,
//     type: CameraType = .orthographic,
// };
//
// pub const CameraType = enum {
//     perspective,
//     orthographic,
// };
//
// pub const OrthographicCamera = CameraMaker(.orthographic);
// pub const PerspectiveCamera = CameraMaker(.perspective);
//
// fn CameraMaker(comptime T: CameraType) type {
//     return struct {
//         const Self = @This();
//         type: CameraType = T,
//         // mvp: Mat4 = Mat4.identity(),
//         // projection_matrix: Mat4 = Mat4.identity(),
//         // view_matrix: Mat4 = Mat4.identity(),
//         mvp: zm.Mat,
//         projection_matrix: zm.Mat,
//         view_matrix: zm.Mat,
//         pos: zm.F32x4 = zm.f32x4(3.0, 3.0, 3.0, 1.0), // eye position
//         look_at: zm.F32x4 = zm.f32x4(0.0, 0.0, 0.0, 1.0), // focus point
//         direction: zm.F32x4 = zm.f32x4(0.0, 1.0, 0.0, 0.0) // up direction ('w' coord is zero because this is a vector not a point)
//         ,
//         // pos: vec.Vec3 = .{ .x = 0, .y = 1.5, .z = 6 },
//         // look_at: vec.Vec3 = vec.Vec3.zero(),
//         // direction: vec.Vec3 = vec.Vec3.up(),
//         viewport: shape.IRect = shape.IRect.zero(),
//         scissor: shape.IRect = .{ .x = 0, .y = 0, .h = 0, .w = 0 },
//
//         pub fn setViewport(self: *Self, vp: shape.IRect) void {
//             self.viewport = vp;
//             self.offsetScissor(vp.x, vp.y);
//             self.computeView();
//             self.computeProj();
//             self.computeMvp();
//         }
//
//         pub fn resetViewport(self: *Self, width: i32, height: i32) void {
//             self.viewport = .{ .x = 0, .y = 0, .w = width, .h = height };
//             self.resetProj();
//             self.resetScissor();
//         }
//
//         fn resetProj(self: *Self) void {
//             const ratio: f32 = if (self.viewport.h != 0) @as(f32, @floatFromInt(self.viewport.w)) / @as(f32, @floatFromInt(self.viewport.h)) else 1;
//             const fov: f32 = std.math.degreesToRadians(70); // We assume the angle view from the eye to the monitor is 45 degrees
//             self.projection_matrix = Mat4.proj(fov, ratio, 0.1, 100);
//         }
//
//         // fn computeProj(self: *Self, fov: f32, aspect_ratio:f32, near: f32, far: f32) void {
//         fn computeProj(self: *Self) void {
//             //TODO
//             // const ratio: f32 = if (self.viewport.h != 0) @divExact(self.viewport.w, self.viewport.h) else 1;
//             // const ratio: f32 = if (self.viewport.h != 0) @as(f32, @floatFromInt(self.viewport.w)) / @as(f32, @floatFromInt(self.viewport.h)) else 1;
//             // const fov: f32 = std.math.degreesToRadians(45); // We assume the angle view from the eye to the monitor is 45 degrees
//             // self.projection_matrix = Mat4.proj(fov, ratio, 0.1, 100);
//
//             // self.proj = Mat4.proj(fov, ratio, 0.1, 100);
//             self.resetProj();
//         }
//
//         /// The formula is:
//         /// 1. Model: Scale * Rotation * Translation
//         /// 2. View: 1) translate the world so that the camera is at the origin; 2) reorient the world so that the camera's forward axis points along Z, right axis points along X, and up axis points along Y. As before, you can come up with these individual transform equations pretty easily and then multiply them together, but it's more efficient to have one formula that builds the entire View Matrix.
//         /// 3. Projection:
//         ///    Rescale the horizontal space so that -1 is the camera's left edge, and +1 is the camera's right edge. Keep in mind that with a perspective projection, the "edges" are constantly widening as you move farther from the camera, so it's not a simple rescaling.
//         ///    Rescale the vertical space so that so that -1 is the camera's bottom edge, and +1 is the camera's top edge (or vice-versa).
//         ///    Rescale the depth (Z axis) so that 0 represents being right in front of the camera, and 1 represents the farthest distance that the camera can see. In some cases, it's not 0 to 1 but -1 to +1, like the other axes. Self transformation is usually *extremely* non-linear, with most of the floating-point precision wasted in the tiny space right in front of the camera. Self makes Z-fighting a common problem for far-away surfaces, due to the lack of precision. There has been some work on using a different depth equation to spread out the values more.
//         fn computeMvp(self: *Self) void {
//
//             //
//             // OpenGL/Vulkan example
//             //
//             // const object_to_world = zm.rotationY(..);
//             const object_to_world: zm.Mat = .{
//                 zm.f32x4(0, 0, 0, 0),
//                 zm.f32x4(0, 0, 0, 0),
//                 zm.f32x4(0, 0, 0, 0),
//                 zm.f32x4(0, 0, 0, 0),
//             };
//
//             self.view_matrix = Mat4.lookat(self.pos, self.look_at, self.direction);
//             // View Matrix
//             const world_to_view = zm.lookAtRh(
//                 zm.f32x4(3.0, 3.0, 3.0, 1.0), // eye position
//                 zm.f32x4(0.0, 0.0, 0.0, 1.0), // focus point
//                 zm.f32x4(0.0, 1.0, 0.0, 0.0), // up direction ('w' coord is zero because this is a vector not a point)
//             );
//             // `perspectiveFovRhGl` produces Z values in [-1.0, 1.0] range (Vulkan app should use `perspectiveFovRh`)
//             const view_to_clip = zm.perspectiveFovRhGl(0.25 * std.math.pi, self.getAspectRatio(), 0.1, 20.0);
//
//             const object_to_view = zm.mul(object_to_world, world_to_view);
//             const object_to_clip = zm.mul(object_to_view, view_to_clip);
//
//             self.mvp = object_to_clip;
//
//             // self.mvp = Mat4.mul(self.projection_matrix, Mat4.mul(self.view_matrix, self.model));
//             // self.mvp = Mat4.mul(self.projection_matrix, self.view_matrix);
//             // log.debug("[Delil.Camera][DEBUG] computeMvp: MVP{}, Projection{},  View{}, Pos{}", .{ self.mvp, self.projection_matrix, self.view_matrix, self.pos });
//
//             // self.mvp = vec.Mat2x3.mul_proj_transform(&self.proj, &self.transform);
//
//         }
//
//         fn computeView(self: *Self) void {
//             self.view_matrix = Mat4.lookat(self.pos, self.look_at, self.direction);
//         }
//
//         pub fn offsetScissor(self: *Self, x: i32, y: i32) void {
//             if (!(self.scissor.w < 0 and self.scissor.h < 0)) {
//                 self.scissor.x += x - self.viewport.x;
//                 self.scissor.y += y - self.viewport.y;
//             }
//         }
//
//         fn getAspectRatio(self: *Self) f32 {
//             return self.viewport.w / self.viewport.h;
//         }
//
//         fn resetScissor(self: *Self) void {
//             self.scissor = .{ .x = 0, .y = 0, .w = -1, .h = -1 };
//         }
//     };
// }
