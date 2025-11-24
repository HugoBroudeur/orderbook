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

pub fn setup(self: *OrderBookSystem, world: *ecs.zflecs.world_t) void {
    _ = &self;
    _ = &world;

    if (!initialised) {
        ecs.logger.err("[OrderBookSystem] Not initialised, you must run .init() before .setup(). System skipped", .{});
        return;
    }

    // _ = ecs.zflecs.ADD_SYSTEM(world, "system_place_order", ecs.zflecs.OnUpdate, system_place_order);

    // ecs.register_observer(world, ecs.components.Event.UnlockResourceEvent, ecs.zflecs.OnAdd, system_on_resource_unlocked);
}

pub fn update(self: *OrderBookSystem, world: *ecs.zflecs.world_t) void {
    _ = &self;
    _ = &world;
}

pub fn system(self: *OrderBookSystem) System {
    return System.init(self);
}

pub fn system_place_order(ctx: struct { cb: *ecs.CmdBuf, market_data: *ecs.components.MarketData, es: *ecs.Entities }, o: *const ecs.components.Event.PlaceOrderEvent, e: ecs.Entity) void {
    ecs.logger.info("[OrderBookSystem.system_place_order]", .{});

    const order = ecs.components.OrderBook.Order.init(ctx.market_data.getNextId(), .GoodTillCancel, o.side, o.price, o.quantity);

    var iter = ctx.es.iterator(struct {
        mt: *ecs.components.MarketTrading,
        unlocked: *ecs.components.Unlocked,
    });
    while (iter.next(ctx.es)) |view| {
        if (o.asset.isEqualTo(view.mt.asset)) {
            const trades = view.mt.book.addOrder(order) catch |err| {
                std.log.err("[ERROR][OrderBookSystem.system_place_order] {}", .{err});
                return;
            };
            ecs.create_single_component_entity(ctx.cb, ecs.components.OrderBook.Trades, trades);
            e.destroy(ctx.cb);
        }
    }
}

// zflecs implementation
// fn system_place_order(it: *ecs.zflecs.iter_t, orders: []ecs.components.Event.PlaceOrderEvent) void {
//     ecs.logger.info("[OrderBookSystem.system_place_order]", .{});
//     const market_data = ecs.zflecs.singleton_ensure(it.world, ecs.components.SingletonMarketData);
//
//     const desc: ecs.zflecs.query_desc_t = .{
//         .terms = init: {
//             var t: [32]ecs.zflecs.term_t = @splat(.{});
//             t[0] = .{ .id = ecs.zflecs.id(ecs.components.MarketTrading) };
//             break :init t;
//         },
//     };
//
//     const query = ecs.zflecs.query_init(it.world, &desc) catch |err| {
//         std.log.err("[ERROR][OrderBookSystem.system_place_order] {}", .{err});
//         return;
//     };
//
//     for (orders) |o| {
//         const order = ecs.components.OrderBook.Order.init(market_data.getNextId(), .GoodTillCancel, o.side, o.price, o.quantity);
//
//         var mt_it = ecs.zflecs.query_iter(it.world, query);
//         while (ecs.zflecs.iter_next(&mt_it)) {
//             const market_tradings = ecs.zflecs.field(&mt_it, ecs.components.MarketTrading, 0).?;
//
//             for (market_tradings) |*m| {
//                 if (m.asset == o.asset) {
//                     const trades = m.book.addOrder(order) catch |err| {
//                         std.log.err("[ERROR][OrderBookSystem.system_place_order] {}", .{err});
//                         return;
//                     };
//                     const entity = ecs.zflecs.new_id(it.world);
//                     _ = ecs.zflecs.set(it.world, entity, ecs.components.OrderBook.Trades, trades);
//
//                     ecs.zflecs.delete(it.world, o.id);
//                     break;
//                 }
//             }
//         }
//
//         // try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(1, .GoodTillCancel, .Buy, 10, 1)));
//         // try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(2, .GoodTillCancel, .Buy, 11, 3)));
//     }
// }

// pub fn system_on_resource_unlocked(ctx: struct { cb: *ecs.CmdBuf, unlock_state: *ecs.components.UnlockState }, ev: *ecs.components.Event.UnlockResourceEvent) void {
//     ecs.logger.print_info("[OrderBookSystem.system_on_resource_unlocked]", .{});
//     // const unlock_state = ecs.zflecs.singleton_ensure(it.world, ecs.components.UnlockState);
//     // const events = ecs.zflecs.field(it, ecs.components.Event.UnlockResourceEvent, 0);
//
//     if (!ctx.unlock_state.is_orderbook_unlocked(ev.asset)) {
//         ctx.unlock_state.unlock_orderbook(ev.asset);
//         // const book = ecs.components.OrderBook.init(allocator, 1) catch |err| {
//         //     ecs.logger.err("[ERROR][OrderbookSystem.system_create_order_book] Can't allocate OrderBook: {})", .{err});
//         //     ecs.throw_error(ctx.cb, ecs.EcsError.AllocationError);
//         //     return;
//         // };
//
//         ecs.logger.print_info("[OrderBookSystem.system_on_resource_unlocked] ev: {any}", .{ev});
//         // ecs.create_single_component_entity(ctx.cb, ecs.components.MarketTrading, .{ .book = book, .asset = ev.asset });
//         // const entity = ecs.zflecs.new_id(it.world);
//         // _ = ecs.zflecs.set(it.world, entity, ecs.components.MarketTrading, .{ .book = book, .asset = ev.asset });
//     }
// }

// zflecs implementation
// fn system_on_resource_unlocked(it: *ecs.zflecs.iter_t) callconv(.c) void {
//     ecs.logger.print_info("[OrderBookSystem.system_on_resource_unlocked]", .{});
//     const unlock_state = ecs.zflecs.singleton_ensure(it.world, ecs.components.UnlockState);
//     const events = ecs.zflecs.field(it, ecs.components.Event.UnlockResourceEvent, 0);
//
//     if (events == null) {
//         return;
//     }
//
//     for (events.?) |ev| {
//         if (!unlock_state.is_orderbook_unlocked(ev.asset)) {
//             unlock_state.unlock_orderbook(ev.asset);
//             const book = ecs.components.OrderBook.init(allocator, 1) catch |err| {
//                 ecs.logger.err("[ERROR][OrderbookSystem.system_create_order_book] Can't allocate OrderBook: {})", .{err});
//                 ecs.throw_error(it.world, ecs.EcsError.AllocationError);
//                 return;
//             };
//
//             ecs.logger.print_info("[OrderBookSystem.system_on_resource_unlocked] ev: {any}", .{ev});
//             const entity = ecs.zflecs.new_id(it.world);
//             _ = ecs.zflecs.set(it.world, entity, ecs.components.MarketTrading, .{ .book = book, .asset = ev.asset });
//         }
//     }
// }

// fn createOrderBook(self: *OrderBookSystem) !ecs.components.OrderBook {
//     const book = try ecs.components.OrderBook.init(self.allocator, 1);
// var book = try OrderBook.init(self.allocator, 1);
// var trades = try std.ArrayList(OrderBook.Trades).initCapacity(self.allocator, 10);
// defer trades.deinit(self.allocator);
//
// try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(1, .GoodTillCancel, .Buy, 10, 1)));
// try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(2, .GoodTillCancel, .Buy, 11, 3)));
// try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(3, .GoodTillCancel, .Buy, 9, 10)));
// try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(4, .GoodTillCancel, .Buy, 13, 10)));
// try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(5, .GoodTillCancel, .Sell, 12, 10)));
// try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(6, .GoodTillCancel, .Sell, 10, 10)));
// try trades.append(allocator, try book.addOrder(orderbook.Order.init(6, .GoodTillCancel, .Sell, 7, 10)));
// _ = try book.addOrder(order);

// std.log.debug("[DEBUG][OrderbookSystem.setup] Trades made: {any}", .{trades});
// std.log.debug("[DEBUG][OrderbookSystem.setup] Trades made on the sell: {any}", .{trades.items[4].items});
// std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[5].items});
// std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[4].items});
//
//     return book;
// }
