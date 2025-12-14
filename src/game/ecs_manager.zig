const std = @import("std");
const DbManager = @import("db_manager.zig");
const RendererManager = @import("renderer_manager.zig");

const EcsManager = @This();

allocator: std.mem.Allocator,
db_manager: *DbManager,
renderer_manager: *RendererManager,

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager, renderer_manager: *RendererManager) EcsManager {
    // es = try zcs.Entities.init(.{ .gpa = allocator });
    //
    // cb = try zcs.CmdBuf.init(.{
    //     .name = "cb",
    //     .gpa = allocator,
    //     .es = &es,
    // });
    //
    return .{
        .allocator = allocator,
        .db_manager = db_manager,
        .renderer_manager = renderer_manager,
    };
}

pub fn deinit(self: EcsManager) void {
    _ = self;
}
