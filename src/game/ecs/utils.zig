const zecs = @import("zecs");
const data = @import("data.zig");
// const log = @import("../debug/log.zig").ecs;

pub fn getPrimaryCamera(reg: *zecs.Registry) ?*data.PerspectiveCamera {
    var view = reg.view(.{ data.Camera, data.PerspectiveCamera }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const cameraConfig = view.getConst(data.Camera, entity);
        const camera = view.get(data.PerspectiveCamera, entity);
        // _ = &camera;
        if (!cameraConfig.primary) {
            continue;
        }

        // log.debug("[ECS.Utils][DEBUG] Camera Found {}", .{camera});
        return camera;
    }

    return null;
}
