const std = @import("std");

const Logger = @This();

var log_render_system = true;
var counter: usize = 0;

var max_logs: usize = 20;

pub fn info(
    comptime format: []const u8,
    args: anytype,
) void {
    counter += 1;
    if (counter > max_logs) {
        return;
    }
    if (!log_render_system) {
        return;
    }
    std.log.info(format, args);
}

pub fn err(
    comptime format: []const u8,
    args: anytype,
) void {
    if (!log_render_system) {
        return;
    }
    std.log.err(format, args);
}

pub fn print_info(
    comptime format: []const u8,
    args: anytype,
) void {
    if (!log_render_system) {
        return;
    }
    std.log.info(format, args);
}
