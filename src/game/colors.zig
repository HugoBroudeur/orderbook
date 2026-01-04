const sdl = @import("sdl3");

const Color = @This();

r: f32,
g: f32,
b: f32,
a: f32,

pub fn fromArray(arr: [4]f32) Color {
    return .{ .r = arr[0], .g = arr[1], .b = arr[2], .a = arr[3] };
}

pub fn toSdl(color: Color) sdl.pixels.FColor {
    return .{ .a = color.a, .b = color.b, .g = color.g, .r = color.r };
}

pub const Transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
pub const Black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
pub const White: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
pub const Teal: Color = .{ .r = 0, .g = 0.5, .b = 0.5, .a = 1 };
