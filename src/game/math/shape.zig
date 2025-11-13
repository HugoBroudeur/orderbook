const std = @import("std");
const math = @import("std").math;
const vec = @import("vec.zig");

pub const Rect = rect(f32);
pub const IRect = rect(i32);

fn rect(comptime T: type) type {
    return struct {
        x: T,
        y: T,
        w: T,
        h: T,

        pub fn zero() rect(T) {
            return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        }
    };
}

// pub const Rect = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };
// pub const IRect = struct { x: i32 = 0, y: i32 = 0, w: i32 = 0, h: i32 = 0 };

pub const Size = struct { w: f32 = 0, h: f32 = 0 };
pub const ISize = struct { w: i32 = 0, h: i32 = 0 };
