// SDL implementation

const std = @import("std");
const sdl = @import("sdl3");

const Framerate = @This();

pub const SKIP_DRAW_FRAME_THREASHOLD = 3_000;
pub const ONE_MILLISECOND = 1_000_000;
pub const ONE_NANOSECOND = 1_000_000_000;

// local state
is_active: bool = true,
target_fps: u32,

// Calculated on start
freq: u64 = 1,
max_accumulated: u64 = 0,
threshold: u64 = 0,

// Tick value
accumulated: u64 = 0,
last_tick: u64,

// Measure time passing
dt: f32 = 0,
seconds: f32 = 0,
seconds_real: f32 = 0,

// Frame Management
update_count: u32 = 0,
frame_lag: u32 = 0,
running_slow: bool = false,
draw_skip: u32 = 0,

pub fn init(fps: u32) Framerate {
    return .{
        .target_fps = fps,
        .last_tick = 0,
    };
}

pub fn on(self: *Framerate) void {
    self.is_active = true;
    self.setTargetFps(self.target_fps);
}
pub fn off(self: *Framerate) void {
    self.is_active = false;
}

pub fn isOn(self: *Framerate) bool {
    return self.is_active;
}

pub fn setTargetFps(self: *Framerate, target_fps: u32) void {
    const freq = sdl.timer.getPerformanceFrequency();
    self.target_fps = target_fps;
    self.freq = freq;
    self.max_accumulated = @intCast(freq / 2);
    self.threshold = freq / @as(u64, self.target_fps);
    self.last_tick = sdl.timer.getPerformanceCounter();
}

pub fn shouldWait(self: *Framerate) bool {
    const pc = sdl.timer.getPerformanceCounter();
    self.accumulated += pc - self.last_tick;
    self.last_tick = pc;

    if (self.accumulated > self.threshold) {
        if (self.accumulated > self.max_accumulated) {
            self.accumulated = self.max_accumulated;
        }

        return false;
    }

    const remaining_ns: u64 = ((self.threshold - self.accumulated) * ONE_NANOSECOND) / self.freq;
    if (remaining_ns > ONE_MILLISECOND) { // sleep if remaining > 1ms
        sdl.timer.delayNanoseconds(remaining_ns);
    }

    return true;
}

pub fn shouldUpdate(self: *Framerate) bool {
    if (self.accumulated >= self.threshold) {
        const dt = self.getDtSinceLastFrame();
        self.accumulated -= self.threshold;
        self.dt = dt;
        self.seconds += self.dt;
        self.seconds_real += self.dt;
        self.update_count += 1;
        return true;
    }

    return false;
}

pub fn shouldDraw(self: *Framerate) bool {
    if (!self.isOn()) return true;
    self.frame_lag += @max(0, self.update_count - 1);
    const dt = self.getDtSinceLastFrame();
    if (self.running_slow) {
        if (self.frame_lag == 0) {
            self.running_slow = false;
        } else if (self.frame_lag > 10) {
            // Supress rendering, give `update` chance to catch up
            self.draw_skip += 1;
            return false;
        }
    } else if (self.frame_lag >= 5) {
        // Consider game running slow when lagging more than 5 frames
        self.running_slow = true;
    }
    if (self.frame_lag > 0 and self.update_count == 1) self.frame_lag -= 1;

    // Set delta time between `draw`
    self.dt = @as(f32, @floatFromInt(self.update_count)) * dt;

    self.draw_skip = 0;
    return true;
}

pub fn getDtSinceLastFrame(self: *Framerate) f32 {
    return @floatCast(
        @as(f64, @floatFromInt(self.threshold)) / @as(f64, @floatFromInt(self.freq)),
    );
}

pub fn skipDrawThreasholdReached(self: *Framerate) bool {
    return self.draw_skip >= SKIP_DRAW_FRAME_THREASHOLD;
}
