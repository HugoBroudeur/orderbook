const std = @import("std");
const System = @import("system.zig");
const ecs = @import("../ecs.zig");

const OrderBookSystem = @This();

var allocator: std.mem.Allocator = undefined;
var initialised: bool = false;

pub fn init(alloc: std.mem.Allocator) OrderBookSystem {
    allocator = alloc;
    initialised = true;
    return .{};
}

pub fn deinit(self: *OrderBookSystem) void {
    _ = self;
    // self.book.deinit();
}

pub fn setup(self: *OrderBookSystem) void {
    _ = &self;

    if (!initialised) {
        ecs.logger.err("[OrderBookSystem] Not initialised, you must run .init() before .setup(). System skipped", .{});
        return;
    }
}

pub fn update(self: *OrderBookSystem) void {
    _ = &self;
}

pub fn system(self: *OrderBookSystem) System {
    return System.init(self);
}

pub fn system_place_order(ctx: struct { cb: *ecs.CmdBuf, market_data: *ecs.components.MarketData, es: *ecs.Entities }, o: *const ecs.components.Event.PlaceOrderEvent, e: ecs.Entity) void {
    ecs.logger.info("[OrderBookSystem.system_place_order]", .{});

    const order = ecs.components.OrderBook.Order.init(ctx.market_data.getNextId(), .GoodTillCancel, o.side, o.price, o.quantity);

    const trades = o.mt_ptr.book.addOrder(order) catch |err| {
        std.log.err("[ERROR][OrderBookSystem.system_place_order] {}", .{err});
        return;
    };
    ecs.create_single_component_entity(ctx.cb, ecs.components.OrderBook.Trades, trades);
    e.destroy(ctx.cb);
}
