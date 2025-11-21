const std = @import("std");
const System = @import("system.zig");
const ecs = @import("ecs");

const OrderBookSystem = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) OrderBookSystem {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *OrderBookSystem) void {
    _ = self;
    // self.book.deinit();
}

pub fn setup(self: *OrderBookSystem, world: *ecs.zflecs.world_t) void {
    _ = &self;
    _ = &world;

    _ = ecs.zflecs.ADD_SYSTEM(world, "system_place_order", ecs.zflecs.OnUpdate, system_place_order);
    _ = ecs.zflecs.ADD_SYSTEM(world, "system_create_order_book", ecs.zflecs.OnUpdate, system_create_order_book);
}

pub fn update(self: *OrderBookSystem, world: *ecs.zflecs.world_t) void {
    _ = &self;
    _ = &world;
}

fn buySystem(market_tradings: []ecs.components.MarketTrading) void {
    _ = market_tradings;

    // for (market_tradings) |*m| {
    // const stats = m.book.snapshot();

    // std.log.debug("[DEBUG][OrderbookSystem.update] Orderbook: size {}", .{m.book.size()});
    // std.log.debug("[DEBUG][OrderbookSystem.update] Stats: {any}", .{stats});
    // }
}

pub fn system(self: *OrderBookSystem) System {
    return System.init(self);
}

fn createOrderBook(self: *OrderBookSystem) !ecs.components.OrderBook {
    const book = try ecs.components.OrderBook.init(self.allocator, 1);
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

    return book;
}

fn system_place_order(it: *ecs.zflecs.iter_t, orders: []ecs.components.Event.PlaceOrderEvent) void {
    ecs.logger.info("[OrderBookSystem.system_place_order]", .{});
    const market_data = ecs.zflecs.singleton_ensure(it.world, ecs.components.SingletonMarketData);

    const desc: ecs.zflecs.query_desc_t = .{
        .terms = init: {
            var t: [32]ecs.zflecs.term_t = @splat(.{});
            t[0] = .{ .id = ecs.zflecs.id(ecs.components.MarketTrading) };
            break :init t;
        },
    };

    const query = ecs.zflecs.query_init(it.world, &desc) catch |err| {
        std.log.err("[ERROR][OrderBookSystem.system_place_order] {}", .{err});
        return;
    };

    for (orders) |o| {
        const order = ecs.components.OrderBook.Order.init(market_data.getNextId(), .GoodTillCancel, o.side, o.price, o.quantity);

        var mt_it = ecs.zflecs.query_iter(it.world, query);
        while (ecs.zflecs.iter_next(&mt_it)) {
            const market_tradings = ecs.zflecs.field(&mt_it, ecs.components.MarketTrading, 0).?;

            for (market_tradings) |*m| {
                if (m.asset == o.asset) {
                    const trades = m.book.addOrder(order) catch |err| {
                        std.log.err("[ERROR][OrderBookSystem.system_place_order] {}", .{err});
                        return;
                    };
                    const entity = ecs.zflecs.new_id(it.world);
                    _ = ecs.zflecs.set(it.world, entity, ecs.components.OrderBook.Trades, trades);

                    ecs.zflecs.delete(it.world, o.id);
                    break;
                }
            }
        }

        // try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(1, .GoodTillCancel, .Buy, 10, 1)));
        // try trades.append(self.allocator, try book.addOrder(OrderBook.Order.init(2, .GoodTillCancel, .Buy, 11, 3)));
    }
}

fn system_create_order_book(self: *OrderBookSystem, it: *ecs.zflecs.iter_t, events: []ecs.components.Event.UnlockResourceEvent) void {
    for (events) |event| {
        const book = try ecs.components.OrderBook.init(self.allocator, 1) catch |err| {
            ecs.logger.err("[ERROR][OrderbookSystem.system_create_order_book] Can't allocate OrderBook: {})", .{err});
            ecs.throw_error(ecs.EcsError.AllocationError);
            return;
        };

        const entity = ecs.zflecs.new_id(self.world);
        _ = ecs.zflecs.set(it.world, entity, ecs.components.MarketTrading, .{ .book = book, .asset = event.asset });
    }
}
