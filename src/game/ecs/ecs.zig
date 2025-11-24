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

// Set the maximum amount of registered system. The allocation is done once
const MAX_SYSTEMS_REGISTERED = 12;

const Ecs = @This();
allocator: std.mem.Allocator,
// reg: zecs.Registry,
world: *zflecs.world_t,

// systems: std.EnumArray(SystemType, System),
systems: std.ArrayList(System),
render_systems: std.ArrayList(RenderSystem),
// input_system: *input_systems.InputSystem = undefined,

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

pub fn init(allocator: std.mem.Allocator) !Ecs {
    es = try zcs.Entities.init(.{ .gpa = allocator });

    cb = try zcs.CmdBuf.init(.{
        .name = "cb",
        .gpa = allocator,
        .es = &es,
    });

    return .{
        .allocator = allocator,
        // .reg = zecs.Registry.init(allocator),
        .systems = try .initCapacity(allocator, MAX_SYSTEMS_REGISTERED),
        // .systems = undefined,
        .render_systems = try .initCapacity(allocator, MAX_SYSTEMS_REGISTERED),
        .world = zflecs.init(),
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
    // self.reg.deinit();
    _ = zflecs.fini(self.world);
}

pub fn build_world(self: *Ecs) !void {
    RenderingPipeline.init(self.world);
    // try self.register_components();
    // try self.register_systems();
    // try self.register_render_systems();

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

    for (self.systems.items) |system| {
        system.setup(self.world);
    }
    for (self.render_systems.items) |*render_system| {
        render_system.setup();
    }

    try self.populate_world(&cb);
}

pub fn progress(self: *Ecs) void {
    _ = self;
    // _ = zflecs.progress(self.world, 0);

    es.forEach("system_unlock_resource", GameSystem.system_unlock_resource, .{
        .cb = &cb,
        .es = &es,
    });

    es.forEach("system_place_order", OrderbookSystem.system_place_order, .{
        .cb = &cb,
        .market_data = &singletons.market_data,
        .es = &es,
    });

    // es.forEach("system_on_resource_unlocked", OrderbookSystem.system_on_resource_unlocked, .{
    //     .cb = &cb,
    //     .unlock_state = &singletons.unlock_state,
    // });

    // self.execCmdBuf();

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
    // UiSystem.start_imgui_pass(.{ .state = &singletons.ui_state });
    es.forEach("render_ui", UiSystem.render_ui, .{
        .cb = &cb,
        .es = &es,
    });
    // UiSystem.render_ui(.{ .state = &singletons.ui_state }, &singletons.pass_action);
    // UiSystem.render_market_view(.{ .cb = &cb, .state = &singletons.ui_state }, &es);
    // UiSystem.system_render_resource_view(.{
    //     .cb = &cb,
    //     .state = &singletons.ui_state,
    //     .unlock_state = &singletons.unlock_state,
    // }, &es);
    //
    // // CmdBuf.Exec.immediate(&es, &cb);
    // UiSystem.end_imgui_pass();

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

fn register_components(self: Ecs) !void {
    // const buy_button = self.reg.create();
    // self.reg.add(buy_button, data.Button{ .label = "Buy" });
    // self.reg.add(buy_button, data.GameObject{});

    // Components
    zflecs.COMPONENT(self.world, components.MarketTrading);
    zflecs.COMPONENT(self.world, components.MarketAsset);
    zflecs.COMPONENT(self.world, components.Resource);
    zflecs.COMPONENT(self.world, components.RecipeInput);
    zflecs.COMPONENT(self.world, components.RecipeOutput);
    zflecs.COMPONENT(self.world, components.Converter);
    zflecs.COMPONENT(self.world, components.Generator);
    zflecs.COMPONENT(self.world, components.OrderBook.Trades);
    zflecs.COMPONENT(self.world, components.OrderBook.Trade);
    zflecs.COMPONENT(self.world, components.Event.PlaceOrderEvent);
    zflecs.COMPONENT(self.world, components.Event.UnlockResourceEvent);

    // Singletons
    // try self.register_singleton(components.SingletonMarketData, .{});
    // try self.register_singleton(components.EnvironmentInfo, .{ .world_time = 0 });
    // try self.register_singleton(components.UIState, .{});
    // try self.register_singleton(components.UnlockState, .{});

    // var pass_action: sg.PassAction = .{};
    // pass_action.colors[0] = .{
    //     .load_action = .CLEAR,
    //     .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    // };
    // try self.register_singleton(sg.PassAction, pass_action);
}

// fn register_singleton(self: Ecs, comptime Component: type, value: Component) !void {
//     // _ = self;
//     // zflecs.COMPONENT(self.world, Component);
//     // zflecs.add_id(self.world, zflecs.id(Component), zflecs.EcsIdSingleton);
//     // _ = zflecs.singleton_set(self.world, Component, value);
//
//     if (singletons.contains(@typeName(Component))) {
//         return;
//     }
//
//     // create_single_component_entity(, Component, value);
//     try singletons.put(self.allocator, @typeName(Component), true);
// }

fn populate_world(self: *Ecs, cmd_buf: *CmdBuf) !void {
    // const entity = zflecs.new_id(self.world);
    // _ = zflecs.set(self.world, entity, components.Event.UnlockResourceEvent, .{ .id = entity, .asset = .aluminium });

    // const assets = @typeInfo(components.MetalTypes).@"enum".fields;

    const pass_action: sg.PassAction = .{ .colors = blk: {
        var c: [8]sg.ColorAttachmentAction = @splat(std.mem.zeroes(sg.ColorAttachmentAction));
        c[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
        };
        break :blk c;
    } };

    create_single_component_entity(cmd_buf, sg.PassAction, pass_action);

    for (std.enums.values(components.MetalTypes)) |m| {
        const book = try components.OrderBook.init(self.allocator, 1);
        const entity: Ecs.Entity = .reserve(cmd_buf);
        _ = entity.add(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .metal = m } });
        _ = entity.add(cmd_buf, components.Locked, .{});

        const res: Ecs.Entity = .reserve(cmd_buf);
        _ = res.add(cmd_buf, components.Resource, .{ .name = @tagName(m), .type = .{ .metal = m } });
        _ = res.add(cmd_buf, components.Locked, .{});
        // create_single_component_entity(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .metal = m } });

    }
    for (std.enums.values(components.WoodTypes)) |m| {
        const book = try components.OrderBook.init(self.allocator, 1);
        const entity: Ecs.Entity = .reserve(cmd_buf);
        _ = entity.add(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .wood = m } });
        _ = entity.add(cmd_buf, components.Locked, .{});
        // create_single_component_entity(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .wood = m } });
        const res: Ecs.Entity = .reserve(cmd_buf);
        _ = res.add(cmd_buf, components.Resource, .{ .name = @tagName(m), .type = .{ .wood = m } });
        _ = res.add(cmd_buf, components.Locked, .{});
    }
    for (std.enums.values(components.ElectronicsTypes)) |m| {
        const book = try components.OrderBook.init(self.allocator, 1);
        const entity: Ecs.Entity = .reserve(cmd_buf);
        _ = entity.add(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .electronics = m } });
        _ = entity.add(cmd_buf, components.Locked, .{});
        // create_single_component_entity(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .electronics = m } });
        const res: Ecs.Entity = .reserve(cmd_buf);
        _ = res.add(cmd_buf, components.Resource, .{ .name = @tagName(m), .type = .{ .electronics = m } });
        _ = res.add(cmd_buf, components.Locked, .{});
    }
    for (std.enums.values(components.OreTypes)) |m| {
        const book = try components.OrderBook.init(self.allocator, 1);
        const entity: Ecs.Entity = .reserve(cmd_buf);
        _ = entity.add(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .ore = m } });
        _ = entity.add(cmd_buf, components.Locked, .{});
        // create_single_component_entity(cmd_buf, components.MarketTrading, .{ .book = book, .asset = .{ .ore = m } });
        const res: Ecs.Entity = .reserve(cmd_buf);
        _ = res.add(cmd_buf, components.Resource, .{ .name = @tagName(m), .type = .{ .ore = m } });
        _ = res.add(cmd_buf, components.Locked, .{});
    }

    create_single_component_entity(cmd_buf, components.Event.UnlockResourceEvent, .{ .asset = .{ .metal = .Iron } });
    create_single_component_entity(cmd_buf, components.Event.UnlockResourceEvent, .{ .asset = .{ .ore = .IronOre } });

    // singletons.orderbooks = .initFull(try components.OrderBook.init(allocator, 1));
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
