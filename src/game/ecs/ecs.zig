const std = @import("std");
const zecs = @import("zecs");
// const logger = @import("../debug/log.zig");
// const log = logger.ecs;
const prefab = @import("prefabs/prefab.zig");
const data = @import("data.zig");
const sokol = @import("sokol");
const sapp = sokol.app;
const simgui = sokol.imgui;
const System = @import("systems/system.zig");
// const delil_pass = @import("../gfx/render_pass.zig");

const render_systems = @import("systems/render_system.zig");
const scenario_render_systems = @import("systems/render/scenario.zig");
const metrics_systems = @import("systems/metrics.zig");
const camera_systems = @import("systems/camera_system.zig");
const input_systems = @import("systems/input_system.zig");
const ui_systems = @import("systems/ui_system.zig");

const Ecs = @This();
allocator: std.mem.Allocator,
reg: zecs.Registry,

// systems: std.ArrayListUnmanaged(System) = undefined,
systems: std.EnumMap(SystemType, System),
// input_system: *input_systems.InputSystem = undefined,

pub const SystemType = enum {
    input,
    camera,
    scenario_render,
    render,
    ui,
    metrics,
};

pub fn init(allocator: std.mem.Allocator) !Ecs {
    return .{
        .allocator = allocator,
        .reg = zecs.Registry.init(allocator),
        .systems = .init(.{}),
    };
}

pub fn deinit(self: *Ecs) void {
    _ = &self;

    self.reg.deinit();
}

pub fn build_world(self: *Ecs) !void {
    self.register_components();
    try self.register_systems();

    var it = self.systems.iterator();
    while (it.next()) |i| {
        std.log.debug("{?}", .{i.key});
        i.value.onSetup(&self.reg);
    }
}

pub fn progress(self: *Ecs) void {
    for (&self.systems.values) |*sys| {
        sys.onFrame(&self.reg);
    }
}

// pub fn render(self: *Ecs, pass: *delil_pass.RenderPass) void {
//     // var previous_pass = pass;
//     _ = &pass;
//     for (&self.systems.values) |*sys| {
//         // previous_pass = sys.onRender(&self.reg, previous_pass);
//         sys.onRender(&self.reg);
//     }
// }

pub fn collect(self: *Ecs, ev: sapp.Event) void {
    // var event = self.reg.singletons().get(data.Event);
    // log.debug("[ECS.ecs][DEBUG] Collect Event {}", .{ev});

    // self.input_system.collectEvent(ev);
    // self.reg.singletons().remove(@TypeOf(ev));
    // self.reg.singletons().remove(@TypeOf(ev));
    // const ie = data.InputEvent{ .code = ev.key_code, .status = ev.type };
    // var ie = self.reg.singletons().get(data.InputEvent);
    // ie.code = ev.key_code;
    // ie.status = ev.type;
    const i = self.reg.singletons().get(data.InputsState);
    // if (ie.status == .KEY_DOWN) {
    //     std.log.info("Key pressed {}", .{ie.code});
    // }

    i.keys.set(ev.key_code, ev.type);

    _ = simgui.handleEvent(ev);

    for (&self.systems.values) |*sys| {
        sys.once(&self.reg);
    }
}

fn register_systems(self: *Ecs) !void {
    // const setup_systems = [_](*const fn (*Ecs) void){
    //     input_systems.setup,
    // };

    // const update_systems = [_](*const fn (*zecs.Registry) void){
    //     metrics_systems.updateEnvironmentInfo,
    //     input_systems.handleInputs,
    //     // camera_systems.updateCamera,
    //     render_systems.render_graph,
    // };

    // for (setup_systems) |f| {
    //     try self.systems.once.append(allocator, f);
    // }

    // for (update_systems) |f| {
    //     try self.systems.each_frame.append(allocator, f);
    // }

    var metricSystem = metrics_systems.MetricSystem.create();
    self.systems.set(.metrics, metricSystem.system());

    // var inputSystem = input_systems.InputSystem.create(allocator);
    // self.systems.set(.input, inputSystem.system());

    // // Special case
    // self.input_system = &inputSystem;

    // var cameraSystem = camera_systems.CameraSystem.create();
    // self.systems.set(.camera, cameraSystem.system());
    // const ss = s.system();

    // var scenarioRenderSystem = scenario_render_systems.ScenarioRenderSystem.create();
    // self.systems.set(.scenario_render, scenarioRenderSystem.system());

    // var renderSystem = render_systems.RenderSystem.create();
    // self.systems.set(.render, renderSystem.system());

    var uiSystem = ui_systems.UiSystem.create();
    self.systems.set(.ui, uiSystem.system());

    // camera_systems.CameraSystem.system();
    // try self.systems.each_frame.append(allocator, ss);
    // try self.systems.each_frame.append(allocator, camera.do);

    // const view = self.reg.view(comptime includes: anytype, comptime excludes: anytype);

    // _ = zflecs.ADD_SYSTEM(zworld, "Render", zflecs.OnUpdate, render_systems.render_scene);
    // _ = zflecs.ADD_SYSTEM(zworld, "debug system", zflecs.OnUpdate, render_systems.debug_system);
    // _ = zflecs.ADD_SYSTEM(zworld, "Tile Render System", zflecs.OnUpdate, render_systems.render_tile);
    // _ = zflecs.ADD_SYSTEM(zworld, "C style render", zflecs.OnUpdate, render_systems.c_render_scene);

    // Execute system Once on startup
    // for (self.systems.once.items) |f| {
    //     f(&self);
    // }
}

fn register_components(self: *Ecs) void {
    // Core
    self.reg.singletons().add(data.EnvironmentInfo{ .world_time = 0 });

    // Camera
    const camera = self.reg.create();
    self.reg.add(camera, data.Camera{ .primary = true, .type = .perspective });
    self.reg.add(camera, data.PerspectiveCamera{});

    for (0..5) |i| {
        const ob = self.reg.create();
        self.reg.add(ob, data.GameObject{ .pos = .{ .x = @as(f32, @floatFromInt(i)) / 10, .y = @as(f32, @floatFromInt(i)) / 10, .z = 0 } });
    }
}
