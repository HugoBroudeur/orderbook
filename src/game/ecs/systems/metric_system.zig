const ecs = @import("../ecs.zig");
const System = @import("system.zig");
const sdl = @import("sdl3");

const MetricSystem = @This();

pub fn init() MetricSystem {
    return .{};
}

pub fn deinit(self: *MetricSystem) void {
    _ = self;
}

pub fn setup(self: *MetricSystem) void {
    _ = &self;
}

pub fn system(self: *MetricSystem) System {
    return System.init(self);
}

pub fn update(self: *MetricSystem) void {
    _ = &self;
}

pub fn system_update_env_info(ctx: struct {}, i: *ecs.components.EnvironmentInfo) void {
    ecs.logger.info("[MetricSystem.system_update_env_info]", .{});
    _ = &ctx;
    // _ = i;

    const previous_time = i.*.world_time;
    const current_time = sdl.timer.getPerformanceCounter();
    const frequency = sdl.timer.getPerformanceFrequency();
    i.world_time = current_time;
    i.dt = (current_time - previous_time) * 1000 / frequency;

    // i.world_time = @floatCast(sokol.time.sec(sokol.time.now()));
    // i.window_width = sapp.width();
    // i.window_height = sapp.height();
}
