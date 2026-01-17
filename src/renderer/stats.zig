const std = @import("std");
const sdl = @import("sdl3");

const Stats = @This();

pub const Timer = enum {
    transfer,
    render_passes,
    render_pass_2d,
    render_pass_ui,
    render_pass_triangle,
    copy_pass,
    frame,
    acquire_cmd_buf,
    acquire_texture,
};
pub const Clock = struct {
    last: u64 = 0,
    last_tick: u64 = 0,
    cur_tick: u64 = 0,
    cur: u64 = 0,

    high_ms: f64 = 0,
    low_ms: f64 = 0,
    average_ms: f64 = 0,

    pub fn reset(self: *Clock) void {
        const time = sdl.timer.getPerformanceCounter();
        self.last = time;
        self.cur = time;

        self.last_tick = time;
        self.cur_tick = time;
    }

    pub fn tick(self: *Clock) void {
        const freq = sdl.timer.getPerformanceFrequency();
        const perf = sdl.timer.getPerformanceCounter();

        self.last_tick = self.cur_tick;

        self.cur = perf;
        self.cur_tick = perf;

        const total_diff_ms = @as(f64, @floatFromInt(self.cur - self.last)) / @as(f64, @floatFromInt(freq)) * 1000.0;
        self.updateTimingStats(total_diff_ms);
    }

    fn updateTimingStats(self: *Clock, ms: f64) void {
        if (self.high_ms == 0 or ms > self.high_ms) self.high_ms = ms;
        if (self.low_ms == 0 or ms < self.low_ms) self.low_ms = ms;

        // exponential moving average (cheap & smooth)
        if (self.average_ms == 0)
            self.average_ms = ms
        else
            self.average_ms = self.average_ms * 0.95 + ms * 0.05;
    }
};

frame_index: u64 = 0,
skip_calculation: bool = false,

// per-frame accumulators
frame_vertices: u32 = 0,
frame_indices: u32 = 0,
frame_draw_calls: u32 = 0,
frame_skipped_draws: u32 = 0,

// per-second counters
sec_start_ticks: u64 = 0,
sec_draw_calls: u32 = 0,
sec_skipped_draws: u32 = 0,
sec_frames: u32 = 0,

high_num_vertices_per_frame: u32 = 0,
high_num_indices_per_frame: u32 = 0,
low_num_vertices_per_frame: u32 = 0,
low_num_indices_per_frame: u32 = 0,
average_num_vertices_per_frame: u32 = 0,
average_num_indices_per_frame: u32 = 0,

draw_call_per_frame: u32 = 0,
skip_draw_per_frame: u32 = 0,
draw_call_per_sec: u32 = 0,
skip_draw_per_sec: u32 = 0,
frame_per_sec: u32 = 0,

total_skip_frame: u64 = 0,
ratio_skip_frame: f64 = 0,

clocks: std.EnumMap(Timer, Clock) = .initFull(.{}),

pub fn init() Stats {
    return .{};
}

pub fn startFrame(self: *Stats) void {
    const now = sdl.timer.getPerformanceCounter();
    self.skip_calculation = false;

    // First frame init
    if (self.frame_index == 0) {
        self.sec_start_ticks = now;
    }

    self.frame_index += 1;

    // // === Update vertex / index stats ===
    // updateStats(
    //     self.frame_vertices,
    //     &self.high_num_vertices_per_frame,
    //     &self.low_num_vertices_per_frame,
    //     &self.average_num_vertices_per_frame,
    //     self.frame_index,
    // );
    //
    // updateStats(
    //     self.frame_indices,
    //     &self.high_num_indices_per_frame,
    //     &self.low_num_indices_per_frame,
    //     &self.average_num_indices_per_frame,
    //     self.frame_index,
    // );
    //
    // // === Accumulate per-second ===
    // self.sec_draw_calls += self.frame_draw_calls;
    // self.sec_skipped_draws += self.frame_skipped_draws;
    //
    // const freq = sdl.timer.getPerformanceFrequency();
    // const elapsed_ticks = now - self.sec_start_ticks;
    //
    // if (elapsed_ticks >= freq) {
    //     self.draw_call_per_sec = self.sec_draw_calls;
    //     self.skip_draw_per_sec = self.sec_skipped_draws;
    //
    //     self.sec_draw_calls = 0;
    //     self.sec_skipped_draws = 0;
    //     self.sec_start_ticks = now;
    // }

    // === Reset per-frame counters ===
    self.frame_vertices = 0;
    self.frame_indices = 0;
    self.frame_draw_calls = 0;
    self.frame_skipped_draws = 0;
}

pub fn endFrame(self: *Stats) void {
    const now = sdl.timer.getPerformanceCounter();
    const freq = sdl.timer.getPerformanceFrequency();

    // ==============================
    // Per-frame vertex/index stats
    // ==============================
    if (!self.skip_calculation) {
        updateStats(
            self.frame_vertices,
            &self.high_num_vertices_per_frame,
            &self.low_num_vertices_per_frame,
            &self.average_num_vertices_per_frame,
            self.frame_index,
        );

        updateStats(
            self.frame_indices,
            &self.high_num_indices_per_frame,
            &self.low_num_indices_per_frame,
            &self.average_num_indices_per_frame,
            self.frame_index,
        );
    }

    // ==============================
    // Draw call counters
    // ==============================

    self.draw_call_per_frame = self.frame_draw_calls;
    self.skip_draw_per_frame = self.frame_skipped_draws;

    self.sec_draw_calls += self.frame_draw_calls;
    self.sec_skipped_draws += self.frame_skipped_draws;

    self.sec_frames += if (self.skip_calculation) 0 else 1;

    self.total_skip_frame += self.frame_skipped_draws;
    self.ratio_skip_frame = (1 - @as(f64, @floatFromInt(self.total_skip_frame)) / @as(f64, @floatFromInt(self.frame_index))) * 100;

    // ==============================
    // Per-second aggregation
    // ==============================

    if (self.sec_start_ticks == 0) {
        self.sec_start_ticks = now;
    }

    const elapsed_ticks = now - self.sec_start_ticks;

    if (elapsed_ticks >= freq) {
        self.draw_call_per_sec = self.sec_draw_calls;
        self.skip_draw_per_sec = self.sec_skipped_draws;
        self.frame_per_sec = self.sec_frames;

        self.sec_frames = 0;
        self.sec_draw_calls = 0;
        self.sec_skipped_draws = 0;
        self.sec_start_ticks = now;
    }

    // ==============================
    // Timing clocks aggregation
    // ==============================

    if (!self.skip_calculation) {
        var it = self.clocks.iterator();
        while (it.next()) |entry| {
            const clock = entry.value;

            if (clock.cur > clock.last) {
                const ms =
                    @as(f64, @floatFromInt(clock.cur - clock.last)) /
                    @as(f64, @floatFromInt(freq)) * 1000.0;

                // High / Low
                if (clock.high_ms == 0 or ms > clock.high_ms)
                    clock.high_ms = ms;
                if (clock.low_ms == 0 or ms < clock.low_ms)
                    clock.low_ms = ms;

                // Exponential moving average (stable & cheap)
                if (clock.average_ms == 0)
                    clock.average_ms = ms
                else
                    clock.average_ms = clock.average_ms * 0.9 + ms * 0.1;
            }
        }
    }
}

pub fn addDrawCall(self: *Stats, vertices: u32, indices: u32) void {
    self.frame_draw_calls += 1;
    self.draw_call_per_frame += 1;
    self.frame_vertices += vertices;
    self.frame_indices += indices;
}

pub fn addSkippedDraw(self: *Stats) void {
    self.frame_skipped_draws += 1;
    self.skip_draw_per_frame += 1;
    self.skip_calculation = true;
}

pub fn samplePrint(self: *Stats, interval: u64) void {
    if (self.frame_index == 0 or
        self.frame_index == 1 or
        self.frame_index == 2 or
        self.frame_index == 3 or
        self.frame_index == 4 or
        self.frame_index == 5 or
        self.frame_index % interval == 0)
    {
        self.print();
    }
}

pub fn print(self: *Stats) void {
    std.log.info(
        \\==================== Renderer Stats ====================
        \\Total:
        \\  Frames:            : {d:>6}
        \\  Skips:             : {d:>6}
        \\  Ratio:             : {d:>6.2}% Success
        \\Frame: (id: {d})
        \\  Draw Calls        : {d:>6}   (skipped {d})
        \\  Vertices          : {d:>6}   avg {d:>6}   min {d:>6}   max {d:>6}
        \\  Indices           : {d:>6}   avg {d:>6}   min {d:>6}   max {d:>6}
        \\
        \\Per Second:
        \\  FPS               : {d:>6}
        \\  Draw Calls        : {d:>6}
        \\  Skipped Draws     : {d:>6}
        \\
        \\Timings (ms):
    ,
        .{
            self.frame_index,
            self.total_skip_frame,
            self.ratio_skip_frame,

            self.frame_index,
            self.draw_call_per_frame,
            self.skip_draw_per_frame,

            self.frame_vertices,
            self.average_num_vertices_per_frame,
            self.low_num_vertices_per_frame,
            self.high_num_vertices_per_frame,

            self.frame_indices,
            self.average_num_indices_per_frame,
            self.low_num_indices_per_frame,
            self.high_num_indices_per_frame,

            self.frame_per_sec,
            self.draw_call_per_sec,
            self.skip_draw_per_sec,
        },
    );

    // Print timers separately to keep it clean
    var it = self.clocks.iterator();
    while (it.next()) |entry| {
        const timer_name = @tagName(entry.key);
        const c = entry.value;

        std.log.info(
            "  {s:<20} | avg {d:>6.2} | min {d:>6.2} | max {d:>6.2}",
            .{
                timer_name,
                c.average_ms,
                c.low_ms,
                c.high_ms,
            },
        );
    }

    std.log.info(
        "==========================================================",
        .{},
    );
}

pub fn startClock(self: *Stats, timer: Timer) void {
    self.clocks.getPtr(timer).?.reset();
}

pub fn tickClock(self: *Stats, timer: Timer) void {
    self.clocks.getPtr(timer).?.tick();
}

fn updateStats(
    value: u32,
    high: *u32,
    low: *u32,
    avg: *u32,
    frame_index: u64,
) void {
    if (frame_index == 1) {
        high.* = value;
        low.* = value;
        avg.* = value;
        return;
    }

    high.* = @max(high.*, value);
    low.* = @min(low.*, value);

    // running average (integer-safe)
    avg.* = @intCast((@as(u64, avg.*) * (frame_index - 1) + value) / frame_index);
}
