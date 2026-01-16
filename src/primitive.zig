const std = @import("std");
const sdl = @import("sdl3");
const zm = @import("zmath");

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    heigth: f32,

    pub fn zero() Rect {
        return .{ .x = 0, .y = 0, .width = 0, .heigth = 0 };
    }

    pub fn eq(self: Rect, rect: Rect) bool {
        return std.meta.eql(self, rect);
    }
};

pub const Point = struct { x: f32, y: f32, z: f32 = 0 };

pub const Circle = struct {};

pub const Triangle = struct {};

pub const Color = struct {
    pub const Transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const Black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const White: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const Red: Color = .{ .r = 1, .g = 0, .b = 0, .a = 1 };
    pub const Green: Color = .{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const Blue: Color = .{ .r = 0, .g = 0, .b = 1, .a = 1 };
    pub const Magenta: Color = .{ .r = 0.5, .g = 0, .b = 0.5, .a = 1 };
    pub const Yellow: Color = .{ .r = 0.5, .g = 0.5, .b = 0, .a = 1 };
    pub const Teal: Color = .{ .r = 0, .g = 0.5, .b = 0.5, .a = 1 };

    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn fromArray(arr: [4]f32) Color {
        return .{ .r = arr[0], .g = arr[1], .b = arr[2], .a = arr[3] };
    }

    pub fn toSdl(color: Color) sdl.pixels.FColor {
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }

    pub fn toVec4(color: Color) zm.F32x4 {
        return zm.f32x4(color.r, color.g, color.b, color.a);
    }
};
