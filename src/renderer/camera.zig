const std = @import("std");

const zm = @import("zmath");
const Rect = @import("../primitive.zig").Rect;

pub const CameraType = enum { orthographic, perspective };

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
        viewport: Rect = Rect.zero(),
        scissor: Rect = Rect.zero(),

        need_compute: bool = true,

        pub fn setViewport(self: *Self, rect: Rect) void {
            if (!self.viewport.eq(rect)) self.need_compute = true;
            self.viewport = rect;
            self.offsetScissor(rect.x, rect.y);
            self.compute(-1, 1);
        }

        pub fn resetViewport(self: *Self, width: f32, height: f32) void {
            self.viewport = .{ .x = 0, .y = 0, .w = width, .h = height };
            self.need_compute = true;
            self.resetScissor();
        }

        fn compute(self: *Self, near: f32, far: f32) void {
            if (!self.need_compute) return;

            self.view_matrix = zm.lookAtRh(self.pos, self.look_at, self.up);

            // Projection (RH, Z = [-1, 1]) For OpenGL/DirectX [0, 1]
            self.projection_matrix = switch (T) {
                .perspective => zm.identity(), // TODO
                .orthographic => zm.orthographicRh(
                    self.viewport.width,
                    self.viewport.heigth,
                    near,
                    far,
                ),
            };

            // self.mvp = zm.mul(self.view_matrix, self.projection_matrix);
            self.mvp = zm.mul(self.projection_matrix, self.view_matrix);

            self.need_compute = false;
        }

        pub fn offsetScissor(self: *Self, x: i32, y: i32) void {
            if (self.scissor.w < 0 or self.scissor.h < 0) {
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
