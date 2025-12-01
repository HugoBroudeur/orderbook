const std = @import("std");
// const zecs = @import("zecs");
pub const zflecs = @import("zflecs");
// const logger = @import("../debug/log.zig");
// const log = logger.ecs;
const prefab = @import("prefabs/prefab.zig");
pub const components = @import("components/components.zig");
pub const logger = @import("logger.zig");
const zcs = @import("zcs");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const simgui = sokol.imgui;
const DbManager = @import("../db_manager.zig");
const System = @import("systems/system.zig");
const RenderSystem = @import("systems/render_system.zig");
const RenderingPipeline = @import("rendering_pipeline.zig");
// const delil_pass = @import("../gfx/render_pass.zig");

// const render_systems = @import("systems/render_system.zig");
// const scenario_render_systems = @import("systems/render/scenario.zig");
const MetricSystem = @import("systems/metric_system.zig");
// const camera_systems = @import("systems/camera_system.zig");
// const input_systems = @import("systems/input_system.zig");
const OrderbookSystem = @import("systems/orderbook_system.zig");
const GameSystem = @import("systems/game_system.zig");
const UiSystem = @import("systems/ui_system.zig");
const SokolRenderSystem = @import("systems/sokol_render_system.zig");

pub const Entities = zcs.Entities;
pub const Entity = zcs.Entity;
pub const CmdBuf = zcs.CmdBuf;
pub const Node = zcs.ext.Node;
pub const TypeId = zcs.typeId;

// Set the maximum amount of registered system. The allocation is done once
const MAX_SYSTEMS_REGISTERED = 12;

const Ecs = @This();
allocator: std.mem.Allocator,

systems: std.ArrayList(System),
render_systems: std.ArrayList(RenderSystem),

db_manager: *DbManager,

pub const ObserverFn = fn (it: *zflecs.iter_t) callconv(.c) void;
pub const EcsError = error{
    AllocationError,
};

pub var es: zcs.Entities = undefined;
pub var cb: zcs.CmdBuf = undefined;

// var singletons: std.StringHashMapUnmanaged(bool) = .{};

pub const singletons = struct {
    pub var env_info: components.EnvironmentInfo = .{ .world_time = 0 };

    pub var market_data: components.MarketData = .{};
};

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager) !Ecs {
    es = try zcs.Entities.init(.{ .gpa = allocator });

    cb = try zcs.CmdBuf.init(.{
        .name = "cb",
        .gpa = allocator,
        .es = &es,
    });

    return .{
        .allocator = allocator,
        .db_manager = db_manager,
        .systems = try .initCapacity(allocator, MAX_SYSTEMS_REGISTERED),
        .render_systems = try .initCapacity(allocator, MAX_SYSTEMS_REGISTERED),
    };
}

pub fn deinit(self: *Ecs) void {
    cb.deinit(self.allocator, &es);
    es.deinit(self.allocator);
    for (self.systems.items) |system| {
        system.deinit();
    }
    self.systems.deinit(self.allocator);
    for (self.render_systems.items) |*system| {
        system.deinit();
    }
    self.render_systems.deinit(self.allocator);
}

pub fn build_world(self: *Ecs) !void {
    //
    // Validate DB
    //
    try self.db_manager.seed_game_db();

    //
    // REGISTER SYSTEMS
    //
    var game_sys = GameSystem.init();
    try self.systems.appendBounded(game_sys.system());

    // var ob_sys = OrderbookSystem.init(self.allocator);
    // try self.systems.appendBounded(ob_sys.system());

    var metric_sys = MetricSystem.init();
    try self.systems.appendBounded(metric_sys.system());

    //
    // REGISTER RENDER SYSTEMS
    //
    var sokol_sys = SokolRenderSystem.init();
    try self.render_systems.appendBounded(sokol_sys.system());

    var ui_sys = UiSystem.init();
    try self.render_systems.appendBounded(ui_sys.system());

    // for (self.systems.items) |system| {
    //     system.setup(self.world);
    // }
    for (self.render_systems.items) |*render_system| {
        render_system.setup();
    }

    try prefab.setup_game(self.allocator, &es, &cb);
}

pub fn progress(self: *Ecs) void {
    _ = self;

    es.forEach("system_update_env_info", MetricSystem.system_update_env_info, .{});

    // es.forEach("system_unlock_asset", GameSystem.system_unlock_asset, .{
    //     .cb = &cb,
    //     .es = &es,
    // });

    es.forEach("system_place_order", OrderbookSystem.system_place_order, .{
        .cb = &cb,
        .market_data = &singletons.market_data,
        .es = &es,
    });

    CmdBuf.Exec.immediate(&es, &cb);
}

pub fn render(self: *Ecs) void {
    _ = self;

    //
    // ALWAYS START WITH A SOKOL PASS
    //
    es.forEach("begin_render_pass", SokolRenderSystem.begin_render_pass, .{ .cb = &cb });
    // SokolRenderSystem.begin_render_pass(&singletons.pass_action);

    //
    // UI SYSTEM PASS
    //
    es.forEach("render_ui", UiSystem.render_ui, .{
        .cb = &cb,
        .es = &es,
    });

    //
    // ALWAYS END WITH A SOKOL PASS
    //
    SokolRenderSystem.render_pass();
    SokolRenderSystem.end_render_pass();

    // for (self.render_systems.items) |*render_system| {
    //     // previous_pass = sys.onRender(&self.reg, previous_pass);
    //     render_system.render(self.world, pass_action);
    // }
}

pub fn execCmdBuf(self: *Ecs) void {
    _ = &self;
    zcs.CmdBuf.Exec.immediate(&es, &cb);
}

pub fn collect(self: *Ecs, ev: sapp.Event) void {
    _ = &self;
    _ = ev;
    // var event = self.reg.singletons().get(data.Event);
    // log.debug("[ECS.ecs][DEBUG] Collect Event {}", .{ev});

    // self.input_system.collectEvent(ev);
    // self.reg.singletons().remove(@TypeOf(ev));
    // self.reg.singletons().remove(@TypeOf(ev));
    // const ie = data.InputEvent{ .code = ev.key_code, .status = ev.type };
    // var ie = self.reg.singletons().get(data.InputEvent);
    // ie.code = ev.key_code;
    // ie.status = ev.type;
    // const i = self.reg.singletons().get(data.InputsState);
    // if (ie.status == .KEY_DOWN) {
    //     std.log.info("Key pressed {}", .{ie.code});
    // }

    // i.keys.set(ev.key_code, ev.type);

    // _ = simgui.handleEvent(ev);

    // for (self.systems.items) |*sys| {
    //     sys.once(&self.reg);
    // }
}

pub fn register_observer(world: *zflecs.world_t, comptime Component: type, event: zflecs.entity_t, run: ObserverFn) void {
    var observer_desc = std.mem.zeroes(zflecs.observer_desc_t);
    observer_desc.query.terms[0] = std.mem.zeroInit(zflecs.term_t, .{ .id = zflecs.id(Component) });

    observer_desc.events[0] = event;
    observer_desc.run = run;

    _ = zflecs.observer_init(world, &observer_desc);
}

// pub fn make_system(comptime Query: type, comptime callback: fn (@typeInfo(Query).@"struct".fields) void) void {
//     // Iterate over entities that contain both transform and node
//     var iter = es.iterator(Query);
//     // var iter = es.iterator(struct {
//     // transform: *Transform,
//     // node: *Node,
//     // });
//     while (iter.next(&es)) |vw| {
//         callback(vw);
//         // You can operate on `vw.transform.*` and `vw.node.*` here!
//         // std.debug.print("transform: {any}\n", .{vw.transform.pos});
//     }
// }

// pub fn get_singleton(comptime C: type) *C {
//     if (singletons.contains(@typeName(C))) {
//         var it = es.iterator(struct { singleton: *C });
//         while (it.next(&es)) |vw| {
//             return vw.singleton;
//         }
//     }
//
//     logger.err("Singleton {s} does not exists", .{@typeName(C)});
//     unreachable;
// }

pub fn create_single_component_entity(cmd_buf: *CmdBuf, comptime C: type, value: C) void {
    const entity: Ecs.Entity = .reserve(cmd_buf);
    _ = entity.add(cmd_buf, C, value);
}

pub fn throw_error(cmb_buf: *Ecs.CmdBuf, err: EcsError) void {
    const e = Ecs.Entity.reserve(cmb_buf);
    _ = e.add(cmb_buf, components.Event.ErrorEvent, .{ .type = err });

    // const entity = zflecs.new_id(world);
    // _ = zflecs.set(world, entity, components.Event.ErrorEvent, .{ .id = entity, .type = err });
}

pub fn register_zflecs_system(world: *zflecs.world_t, name: [*:0]const u8, callback: zflecs.iter_action_t, update_ctx: anytype, terms: []const zflecs.term_t) zflecs.entity_t {
    var system_desc = zflecs.system_desc_t{};
    system_desc.callback = callback;
    system_desc.ctx = update_ctx;
    for (terms, 0..) |term, index| {
        system_desc.query.terms[index] = term;
    }

    const system_ent = zflecs.SYSTEM(world, name, zflecs.OnUpdate, &system_desc);
    return system_ent;
}
