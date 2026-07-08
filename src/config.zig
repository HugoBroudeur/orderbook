const std = @import("std");

const Config = @This();
http_max_threads_count: usize,
sqlite_game_db_path: [:0]const u8,
home_path: []const u8,
base_project_path: []const u8,
default_project_name: []const u8,

pub const log: struct {
    mesh: bool = true,
    buffer: bool = false,
} = .{};

pub fn init(map: *std.process.Environ.Map) Config {
    const val = map.get("HTTP_MAX_THREAD_COUNT");
    const threads = if (val != null) std.fmt.parseInt(usize, val.?, 10) catch 1 else 1;
    return .{
        .http_max_threads_count = threads,
        .sqlite_game_db_path = "db/game_db.sqlite",
        .home_path = map.get("HOME") orelse "",
        .base_project_path = "$HOME/saved_projects/",
        .default_project_name = "price_is_power",
    };
}
