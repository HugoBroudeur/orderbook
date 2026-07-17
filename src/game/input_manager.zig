const std = @import("std");
const DbManager = @import("db_manager.zig");
// const RendererManager = @import("renderer_manager.zig");
const MarketManager = @import("market_manager.zig");
const Ecs = @import("ecs/ecs.zig");
const Prefab = @import("ecs/prefabs/prefab.zig");
const OrderbookSystem = @import("ecs/systems/orderbook_system.zig");
const MetricSystem = @import("ecs/systems/metric_system.zig");
const GraphicsContext = @import("../core/graphics_context.zig");

const zcs = @import("zcs");

const EcsManager = @This();

allocator: std.mem.Allocator,
db_manager: *DbManager,
// renderer_manager: *RendererManager,
market_manager: *MarketManager,
entities: zcs.Entities,
cmd_buf: zcs.CmdBuf,

pub fn init(allocator: std.mem.Allocator, db_manager: *DbManager, market_manager: *MarketManager) !EcsManager {
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
        .market_manager = market_manager,
        .entities = es,
        .cmd_buf = cb,
    };
}

pub fn deinit(self: *EcsManager) void {
    self.cmd_buf.deinit(self.allocator, &self.entities);
    self.entities.deinit(self.allocator);
}

pub fn setup(self: *EcsManager) !void {
    try Prefab.setup_game(self.allocator, &self.entities, &self.cmd_buf);
    self.create_single_component_entity(Ecs.components.EnvironmentInfo, .{});
    self.create_single_component_entity(Ecs.components.Graphics.DrawData, .{});
    self.create_single_component_entity(Ecs.components.MarketData, .{});

    self.flush_cmd_buf();
}

pub fn progress(self: *EcsManager) void {
    self.entities.forEach("system_update_env_info", MetricSystem.system_update_env_info, .{});

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

pub fn create_single_component_entity(self: *EcsManager, comptime C: type, value: C) void {
    const entity: Ecs.Entity = .reserve(&self.cmd_buf);
    _ = entity.add(&self.cmd_buf, C, value);
}

pub fn flush_cmd_buf(self: *EcsManager) void {
    Ecs.CmdBuf.Exec.immediate(&self.entities, &self.cmd_buf);
}
