const std = @import("std");
const DbManager = @import("db_manager.zig");
// const RendererManager = @import("renderer_manager.zig");
const MarketManager = @import("market_manager.zig");
const SceneManager = @import("../engine/scene_manager.zig");
const Ecs = @import("ecs/ecs.zig");
const Prefab = @import("ecs/prefabs/prefab.zig");
const OrderbookSystem = @import("ecs/systems/orderbook_system.zig");
const MetricSystem = @import("ecs/systems/metric_system.zig");
const CameraSystem = @import("ecs/systems/camera_system.zig");
const InputSystem = @import("ecs/systems/input_system.zig");
const Event = @import("../events/event.zig");

const zcs = @import("zcs");

const EcsManager = @This();

allocator: std.mem.Allocator,
db_manager: *DbManager,
// renderer_manager: *RendererManager,
market_manager: *MarketManager,
scene_manager: *SceneManager,
entities: zcs.Entities,
cmd_buf: zcs.CmdBuf,

camera_system: CameraSystem = undefined,
input_system: InputSystem = undefined,

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager, market_manager: *MarketManager, scene_manager: *SceneManager) !EcsManager {
    var es = try zcs.Entities.init(.{ .gpa = allocator });

    const cb = try zcs.CmdBuf.init(.{
        .name = "cb",
        .gpa = allocator,
        .es = &es,
    });

    return .{
        .allocator = allocator,
        .db_manager = db_manager,
        // .renderer_manager = renderer_manager,
        .scene_manager = scene_manager,
        .market_manager = market_manager,
        .entities = es,
        .cmd_buf = cb,
    };
}

pub fn deinit(self: *EcsManager) void {
    self.cmd_buf.deinit(self.allocator, &self.entities);
    self.entities.deinit(self.allocator);
    self.camera_system.deinit();
    self.input_system.deinit();
}

pub fn setup(self: *EcsManager) !void {
    try Prefab.setup_game(self.allocator, &self.entities, &self.cmd_buf);
    self.create_single_component_entity(Ecs.components.EnvironmentInfo, .{});
    self.create_single_component_entity(Ecs.components.Graphics.DrawData, .{});
    self.create_single_component_entity(Ecs.components.MarketData, .{});

    self.flush_cmd_buf();

    // Register Systems
    self.input_system = InputSystem.init(self);
    self.input_system.setup();
    self.camera_system = CameraSystem.init(self);
    self.camera_system.setup();
}

pub fn progress(self: *EcsManager) void {
    self.entities.forEach("system_update_env_info", MetricSystem.system_update_env_info, .{});

    self.input_system.update();
    self.camera_system.update();

    self.entities.forEach("system_place_order", OrderbookSystem.system_place_order, .{
        .cb = &self.cmd_buf,
        .es = &self.entities,
        .market_data = self.get_singleton(Ecs.components.MarketData),
    });

    self.flush_cmd_buf();
}

pub fn get_singleton(self: *EcsManager, comptime T: type) *T {
    var iter = self.entities.iterator(struct {
        type: *T,
    });
    while (iter.next(&self.entities)) |vw| {
        return vw.type;
    }

    unreachable;
}

pub fn handleEvent(self: *EcsManager, ev: Event) bool {
    const input_processed = self.input_system.process(ev);
    const camera_processed = self.camera_system.process(ev);

    return input_processed or camera_processed;
}

pub fn create_single_component_entity(self: *EcsManager, comptime C: type, value: C) void {
    const entity: Ecs.Entity = .reserve(&self.cmd_buf);
    _ = entity.add(&self.cmd_buf, C, value);
}

pub fn createEntity(self: *EcsManager) Ecs.Entity {
    return Ecs.Entity.reserve(&self.cmd_buf);
}

pub fn addComponent(self: *EcsManager, entity: Ecs.Entity, comptime Component: type, value: Component) void {
    _ = entity.add(&self.cmd_buf, Component, value);
}

pub fn getDeltaTime(self: *EcsManager) u64 {
    const env = self.get_singleton(Ecs.components.EnvironmentInfo);
    return env.dt;
}

pub fn flush_cmd_buf(self: *EcsManager) void {
    Ecs.CmdBuf.Exec.immediate(&self.entities, &self.cmd_buf);
}
