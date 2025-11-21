const std = @import("std");
// const zecs = @import("zecs");
pub const zflecs = @import("zflecs");
// const logger = @import("../debug/log.zig");
// const log = logger.ecs;
const prefab = @import("prefabs/prefab.zig");
pub const components = @import("components/components.zig");
pub const logger = @import("logger.zig");
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

pub const EcsError = error{
    AllocationError,
};

pub fn init(allocator: std.mem.Allocator) !Ecs {
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
    self.register_components();
    // try self.register_systems();
    // try self.register_render_systems();

    //
    // REGISTER SYSTEMS
    //
    var game_sys = GameSystem.init();
    try self.systems.appendBounded(game_sys.system());

    var ob_sys = OrderbookSystem.init(self.allocator);
    try self.systems.appendBounded(ob_sys.system());

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
        render_system.setup(self.world);
    }
}

pub fn progress(self: *Ecs) void {
    _ = zflecs.progress(self.world, 0);
}

pub fn render(self: *Ecs, pass_action: *sg.PassAction) void {
    for (self.render_systems.items) |*render_system| {
        // previous_pass = sys.onRender(&self.reg, previous_pass);
        render_system.render(self.world, pass_action);
    }
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

fn register_components(self: Ecs) void {
    // const buy_button = self.reg.create();
    // self.reg.add(buy_button, data.Button{ .label = "Buy" });
    // self.reg.add(buy_button, data.GameObject{});

    // OrderBook
    const book = self.createOrderBook() catch |err| {
        std.log.err("[ERROR][OrderbookSystem.setup] Init OrderBook: {})", .{err});
        return;
    };
    std.log.info("Book ? {any}", .{book});

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

    // Entities
    const entity = zflecs.new_id(self.world);
    _ = zflecs.set(self.world, entity, components.MarketTrading, .{ .book = book, .asset = components.MetalTypes.aluminium });

    const e = zflecs.new_id(self.world);
    _ = zflecs.set(self.world, e, components.Resource, .{ .asset = .aluminium });

    // Singletons
    self.register_singleton(components.SingletonMarketData, .{});
    self.register_singleton(components.EnvironmentInfo, .{ .world_time = 0 });
    self.register_singleton(components.UIState, .{});
    self.register_singleton(components.UnlockState, .{});
    // self.register_singleton(components.MetalTypes, .{});

    var pass_action: sg.PassAction = .{};
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };
    self.register_singleton(sg.PassAction, pass_action);
}

fn register_singleton(self: Ecs, comptime Component: type, value: Component) void {
    zflecs.COMPONENT(self.world, Component);
    zflecs.add_id(self.world, zflecs.id(Component), zflecs.EcsIdSingleton);
    _ = zflecs.singleton_set(self.world, Component, value);
}

pub const ObserverFn = fn (it: *zflecs.iter_t) callconv(.c) void;

pub fn register_observer(self: *Ecs, comptime Component: type, event: zflecs.entity_t, run: ObserverFn) void {
    var observer_desc = std.mem.zeroes(zflecs.observer_desc_t);
    observer_desc.query.terms[0] = std.mem.zeroInit(zflecs.term_t, .{ .id = zflecs.id(Component) });

    observer_desc.events[0] = event;
    observer_desc.run = run;

    _ = zflecs.observer_init(self.world, &observer_desc);
}

pub fn register_system(world: *zflecs.world_t, name: [*:0]const u8, callback: zflecs.iter_action_t, update_ctx: anytype, terms: []const zflecs.term_t) zflecs.entity_t {
    var system_desc = zflecs.system_desc_t{};
    system_desc.callback = callback;
    system_desc.ctx = update_ctx;
    for (terms, 0..) |term, index| {
        system_desc.query.terms[index] = term;
    }

    const system_ent = zflecs.SYSTEM(world, name, zflecs.OnUpdate, &system_desc);
    return system_ent;
}

pub fn throw_error(self: *Ecs, err: EcsError) void {
    const entity = zflecs.new_id(self.world);
    _ = zflecs.set(self.world, entity, components.Event.ErrorEvent, .{ .id = entity, .type = err });
}
