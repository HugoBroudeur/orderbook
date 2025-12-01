const std = @import("std");

const Config = @This();
http_max_threads_count: usize,
sqlite_game_db_path: [:0]const u8,

pub fn init() Config {
    const threads = std.process.parseEnvVarInt("HTTP_MAX_THREAD_COUNT", usize, 10) catch 1;
    return .{
        .http_max_threads_count = threads,
        .sqlite_game_db_path = "db/game_db.sqlite",
    };
}
