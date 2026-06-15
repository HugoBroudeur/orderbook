const std = @import("std");

const zm = @import("zmath");
const IRect = @import("../primitive.zig").IRect;

pub const CameraType = enum { orthographic, perspective };
pub const PerspectiveCamera = Camera(.perspective);
pub const OrthographicCamera = Camera(.perspective);

pub fn Camera(comptime T: CameraType) type {
    return struct {
        const Self = @This();
        name: []const u8 = @tagName(T),

        mvp: zm.Mat = zm.identity(),
        projection_matrix: zm.Mat = zm.identity(),
        view_matrix: zm.Mat = zm.identity(),
        /// eye position
        pos: zm.F32x4 = zm.f32x4(0.0, 0.0, 0.0, 1.0),
        /// focus point
        look_at: zm.F32x4 = zm.f32x4(0.0, 0.0, 0.0, 1.0),
        /// up direction ('w' coord is zero because this is a vector not a point)
        up: zm.F32x4 = zm.f32x4(0.0, 1.0, 0.0, 0.0),
        viewport: IRect = IRect.zero(),
        scissor: IRect = IRect.zero(),

        near: f32 = -1,
        far: f32 = 1,
        fov: f32 = 70,

        need_compute: bool = true,
        is_locked: bool = false,

        pub fn setViewport(self: *Self, rect: IRect) void {
            if (!self.viewport.eq(rect)) self.need_compute = true;
            self.viewport = rect;
            self.offsetScissor(rect.x, rect.y);
            self.compute();
        }

        pub fn resetViewport(self: *Self, width: f32, height: f32) void {
            self.viewport = .{ .x = 0, .y = 0, .w = width, .h = height };
            self.need_compute = true;
            self.resetScissor();
        }

        fn compute(self: *Self) void {
            if (!self.need_compute) return;

            const rot_matrix = zm.matFromQuat(self.look_at);
            const forward = zm.normalize3(zm.mul(zm.f32x4(0, 0, -1, 0), rot_matrix));
            self.view_matrix = zm.lookToRh(self.pos, forward, self.up);

            // self.view_matrix = zm.lookAtRh(self.pos, self.look_at, self.up);

            // Projection (RH, Z = [-1, 1]) For OpenGL/DirectX [0, 1]
            self.projection_matrix = switch (T) {
                .perspective => zm.perspectiveFovRh(
                    self.fov * (std.math.pi / 180.0),
                    @as(f32, @floatFromInt(self.viewport.width)) / @as(f32, @floatFromInt(self.viewport.heigth)),
                    self.near,
                    self.far,
                ),
                .orthographic => zm.orthographicRh(
                    self.viewport.width,
                    self.viewport.heigth,
                    -1, // near
                    1, // far
                ),
            };

            // zmath uses row-vector convention: zm.mul(A, B) means apply A then B.
            // So view-then-projection composes as zm.mul(view, projection).
            self.mvp = zm.mul(self.view_matrix, self.projection_matrix);

            self.need_compute = false;
        }

        pub fn setFov(self: *Self, fov_degrees: f32) void {
            self.fov = fov_degrees;
            self.need_compute = true;
        }

        pub fn setLookAt(self: *Self, yaw: f32, pitch: f32) void {
            // fairly typical FPS style camera. we join the pitch and yaw rotations into
            // the final rotation matrix

            const yaw_rotation = zm.quatFromAxisAngle(.{ 0, -1, 0, 0 }, yaw);
            const pitch_rotation = zm.quatFromAxisAngle(.{ 1, 0, 0, 0 }, pitch);

            self.look_at = zm.qmul(yaw_rotation, pitch_rotation);

            self.need_compute = true;
        }

        pub fn getViewMatrix(self: *Self) zm.Mat {
            self.compute();
            return self.view_matrix;
        }

        pub fn getProjectionMatrix(self: *Self) zm.Mat {
            self.compute();
            return self.projection_matrix;
        }

        pub fn getViewProjMatrix(self: *Self) zm.Mat {
            self.compute();
            return self.mvp;
        }

        pub fn offsetScissor(self: *Self, x: i32, y: i32) void {
            if (self.scissor.width < 0 or self.scissor.heigth < 0) {
                return;
            }
            self.scissor.x += x - self.viewport.x;
            self.scissor.y += y - self.viewport.y;
        }

        fn getAspectRatio(self: *Self) f32 {
            return self.viewport.w / self.viewport.h;
        }

        fn resetScissor(self: *Self) void {
            self.scissor = .{ .x = 0, .y = 0, .w = -1, .h = -1 };
        }
    };
}
