const sokol = @import("sokol");
const sapp = sokol.app;
const zecs = @import("zecs");
const data = @import("../data.zig");
const System = @import("system.zig");

pub const MetricSystem = struct {
    pub fn create() MetricSystem {
        return .{};
    }

    pub fn system(self: *MetricSystem) System {
        return .{
            .ptr = self,
            .vtable = &.{
                .onSetup = onSetup,
                .onFrame = onFrame,
            },
        };
    }

    fn onSetup(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *MetricSystem = @ptrCast(@alignCast(ctx));
        _ = reg;
        _ = self;
    }

    fn onFrame(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *MetricSystem = @ptrCast(@alignCast(ctx));
        _ = self;

        const width = sapp.width();
        const height = sapp.height();

        var i = reg.singletons().get(data.EnvironmentInfo);
        i.world_time = @floatCast(sokol.time.sec(sokol.time.now()));
        i.window_width = width;
        i.window_height = height;
    }
};
