const ecs = @import("../ecs.zig");
const System = @import("system.zig");

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
    _ = i;
    // i.world_time = @floatCast(sokol.time.sec(sokol.time.now()));
    // i.window_width = sapp.width();
    // i.window_height = sapp.height();
}
