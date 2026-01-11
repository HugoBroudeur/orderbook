const std = @import("std");

pub const CameraType = enum { orthographic, perspective };

pub fn Camera(comptime T: CameraType) type {
    return struct {
        name: []const u8 = @tagName(T),
    };
}
