const std = @import("std");
const Uuid = @import("uuid");

const AssetManager = @This();

allocator: std.mem.Allocator,
io: std.Io,

pub fn init(allocator: std.mem.Allocator, io: std.Io) AssetManager {
    return .{
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *AssetManager) void {
    _ = self;
}

pub fn saveAssetPool(self: *AssetManager, project_path: []const u8) !void {
    _ = self;
    _ = project_path;
}
