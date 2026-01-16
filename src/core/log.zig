const std = @import("std");
const sdl = @import("sdl3");

pub const Timer = enum { transfer, render_pass, copy_pass, frame, acquire_cmd_buf, acquire_texture };
pub const Type = enum { start, stop, tick };
pub const Clock = struct {
    last: u64 = 0,
    last_tick: u64 = 0,
    cur_tick: u64 = 0,
    cur: u64 = 0,

    pub fn reset(self: *Clock) void {
        const time = sdl.timer.getPerformanceCounter();
        self.last = time;
        self.cur = time;

        self.last_tick = time;
        self.cur_tick = time;
    }

    pub fn tick(self: *Clock) void {
        const perf = sdl.timer.getPerformanceCounter();

        self.last_tick = self.cur_tick;

        self.cur = perf;
        self.cur_tick = perf;
    }

    pub fn printStop(self: *Clock, name: []const u8) void {
        const freq = sdl.timer.getPerformanceFrequency();

        const total_diff_ms = @as(f64, @floatFromInt(self.cur - self.last)) / @as(f64, @floatFromInt(freq)) * 1000.0;

        std.log.debug("[Timer] {s} | Total Elapsed: {d:.2}ms", .{ name, total_diff_ms });
    }

    pub fn printTick(self: *Clock, name: []const u8) void {
        const freq = sdl.timer.getPerformanceFrequency();

        const tick_diff_ms = @as(f64, @floatFromInt(self.cur_tick - self.last_tick)) / @as(f64, @floatFromInt(freq)) * 1000.0;

        std.log.debug("[Timer] {s} | Tick: {d:.2}ms", .{ name, tick_diff_ms });
    }
};

var clocks: std.EnumMap(Timer, Clock) = .initFull(.{});

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
            // incr();
            // if (!print) return;
            std.log.err(format, args);
        }

        pub fn err_inf(
            comptime format: []const u8,
            args: anytype,
        ) void {
            std.log.err(format, args);
        }

        fn incr() void {
            cur += 1;
            if (cur > max) print = false;
        }

        pub fn timing(
            name: []const u8,
            timer: Timer,
            time_type: Type,
        ) void {
            var t = clocks.getPtr(timer).?;
            switch (time_type) {
                .start => {
                    t.reset();
                },
                .tick => {
                    t.tick();
                    t.printTick(name);
                },
                .stop => {
                    t.tick();
                    t.printStop(name);
                },
            }
        }
    };
}
