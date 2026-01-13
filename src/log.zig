const std = @import("std");

pub fn MaxLogs(comptime MAX: usize) type {
    return struct {
        const Logger = @This();

        var max: usize = MAX;
        var cur: usize = 0;
        var print: bool = true;

        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            incr();
            if (!print) return;
            std.log.info(format, args);
        }

        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            incr();
            if (!print) return;
            std.log.info(format, args);
        }

        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            incr();
            if (!print) return;
            std.log.err(format, args);
        }

        fn incr() void {
            cur += 1;
            if (cur > max) print = false;
        }
    };
}
