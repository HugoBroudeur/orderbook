const sokol = @import("sokol");
const sapp = sokol.app;
const f = @import("zflecs");
const components = @import("../components/components.zig");
const System = @import("system.zig");

const MetricSystem = @This();

pub fn init() MetricSystem {
    return .{};
}

pub fn deinit(self: *MetricSystem) void {
    _ = self;
}

pub fn setup(self: *MetricSystem, world: *f.world_t) void {
    _ = &self;
    _ = &world;

    _ = f.ADD_SYSTEM(world, "system_update_env_info", f.OnLoad, system_update_env_info);
}

pub fn system(self: *MetricSystem) System {
    return System.init(self);
}

pub fn update(self: *MetricSystem, world: *f.world_t) void {
    _ = &self;
    _ = &world;
}

fn system_update_env_info(it: *f.iter_t) void {
    var i = f.singleton_ensure(it.world, components.EnvironmentInfo);
    i.world_time = @floatCast(sokol.time.sec(sokol.time.now()));
    i.window_width = sapp.width();
    i.window_height = sapp.height();
}
