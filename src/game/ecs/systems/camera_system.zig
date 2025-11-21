const zecs = @import("zecs");
const data = @import("../data.zig");
// const log = @import("../../debug/log.zig").ecs;
const System = @import("system.zig");
const ig = @import("cimgui");

pub const CameraSystem = struct {
    const Self = @This();
    camera: *data.PerspectiveCamera = undefined,

    pub fn create() CameraSystem {
        return .{};
    }

    pub fn system(self: *CameraSystem) System {
        return .{
            .ptr = self,
            .vtable = &.{
                .onSetup = onSetup,
                .onFrame = onFrame,
            },
        };
    }

    fn onSetup(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *CameraSystem = @ptrCast(@alignCast(ctx));
        _ = reg;
        _ = self;
    }

    fn onFrame(ctx: *anyopaque, reg: *zecs.Registry) void {
        const self: *CameraSystem = @ptrCast(@alignCast(ctx));
        // const self: *CameraSystem = @ptrCast(@alignCast(ctx));
        // _ = reg;
        _ = &self;
        // _ = &reg;
        // log.debug("[ECS.System][DEBUG] Hello from zecs System ", .{});

        const i = reg.singletons().getConst(data.EnvironmentInfo);
        // log.debug("[ECS.System][DEBUG] World time {}", .{i.world_time});

        // self.updatePrimaryCamera(reg);

        // Reset viewport
        self.camera.resetViewport(i.window_width, i.window_height);

        //TODO, change that to collect commands? Set viewport
        self.camera.setViewport(.{ .x = 0, .y = 0, .w = i.window_width, .h = i.window_height });
        self.handleCameraControl(reg);
        // self.renderCameraControlUi();
    }

    // fn updatePrimaryCamera(self: *Self, reg: *zecs.Registry) void {
    //     // if (utils.getPrimaryCamera(reg)) |camera| {
    //     self.camera = camera;
    // }
    // }

    fn handleCameraControl(self: *Self, reg: *zecs.Registry) void {
        const is = reg.singletons().getConst(data.InputsState);
        if (is.keys.get(.D) == .KEY_DOWN) {
            self.camera.pos.x += 0.01;
        }
        if (is.keys.get(.T) == .KEY_DOWN) {
            self.camera.pos.x -= 0.01;
        }
        if (is.keys.get(.R) == .KEY_DOWN) {
            self.camera.pos.y += 0.01;
        }
        if (is.keys.get(.S) == .KEY_DOWN) {
            self.camera.pos.y -= 0.01;
        }
    }
};

pub fn updateCamera(reg: *zecs.Registry) void {
    _ = &reg;
    // log.debug("[ECS.System][DEBUG] Hello from zecs System ", .{});

    var view = reg.view(.{ data.Camera, data.PerspectiveCamera }, .{});
    var it = view.entityIterator();

    // const i = reg.singletons().getConst(data.EnvironmentInfo);
    // log.debug("[ECS.System][DEBUG] World time {}", .{i.world_time});

    while (it.next()) |entity| {
        const cameraConfig = view.getConst(data.Camera, entity);
        // const camera = view.getConst(data.PerspectiveCamera, entity);
        if (!cameraConfig.primary) {
            continue;
        }

        // camera
        // log.debug("[ECS.System][DEBUG] Camera Found {}", .{camera});
        // const mvp = gfx.camera.mvp; // copy to stack for more efficiency
        // var region: Region = .{ .x1 = f32_max, .y1 = f32_max, .x2 = -f32_max, .y2 = -f32_max };
        // Check if camera.type == gfx.camera.type
        break;
    }
}
