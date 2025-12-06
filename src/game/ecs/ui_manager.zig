const std = @import("std");
const Components = @import("components/components.zig");
const DbManager = @import("../db_manager.zig");
const UiManager = @This();

allocator: std.mem.Allocator,
db_manager: *DbManager,

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager) UiManager {
    return .{
        .allocator = allocator,
        .db_manager = db_manager,
    };
}

pub fn deinit(self: *UiManager) void {
    _ = &self;
}

pub fn on_load(self: *UiManager) !void {
    _ = &self;
}
