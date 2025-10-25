const std = @import("std");

pub const OrderType = enum {
    GoodTillCancel,
    FillAndKill,
};

pub const Side = enum { Buy, Sell };

pub const Price = i32;
pub const Quantity = u32;
pub const OrderId = u32;

pub const OrderError = error{
    OutOfMemory,
    InvalidPrice,
    InvalidAmount,
    QuantityExceedRemaining,
    OrderNotFound,
    DuplicateOrder,
    NoBestBid,
    NoBestAsk,
    LastTradeNotImplemented,
};

// const LevelInfos = std.AutoArrayHashMap(Price, Orders);
//
//
// const OrderPointer = std.heap.(Order);
// const OrderPointers = std.ArrayList(OrderPointer);

pub const Order = struct {
    const Self = @This();

    id: OrderId,
    order_type: OrderType,
    side: Side,
    price: Price,
    initial_quantity: Quantity,
    remaining_quantity: Quantity,

    pub fn init(
        id: OrderId,
        order_type: OrderType,
        side: Side,
        price: Price,
        quantity: Quantity,
    ) Self {
        return .{
            .id = id,
            .order_type = order_type,
            .side = side,
            .price = price,
            .initial_quantity = quantity,
            .remaining_quantity = quantity,
        };
    }

    pub fn deinit(allocator: std.mem.Allocator) void {
        _ = allocator;
    }

    pub fn getFilledQuantity(self: Self) Quantity {
        return self.initial_quantity - self.remaining_quantity;
    }

    pub fn fill(self: *Self, quantity: Quantity) OrderError!void {
        if (quantity > self.remaining_quantity) {
            return OrderError.QuantityExceedRemaining;
        }

        self.remaining_quantity -= quantity;
    }

    pub fn isFilled(self: Self) bool {
        return self.remaining_quantity == 0;
    }
};

const OrderKey = struct { id: OrderId, price: Price };

const Orders = std.AutoArrayHashMap(OrderKey, Order);
const OrderEntry = struct { key: OrderKey, order: Order };

const OrderModify = struct {
    const Self = @This();

    id: OrderId,
    order_type: OrderType,
    price: Price,
    quantity: Quantity,

    pub fn init(
        id: OrderId,
        order_type: OrderType,
        price: Price,
        quantity: Quantity,
    ) Self {
        return .{
            .id = id,
            .order_type = order_type,
            .price = price,
            .quantity = quantity,
        };
    }

    pub fn toOrder(self: Self, side: Side) Order {
        return .{
            .id = self.id,
            .price = self.price,
            .initial_quantity = self.quantity,
            .remaining_quantity = self.quantity,
            .order_type = self.order_type,
            .side = side,
        };
    }
};

const TradeInfo = struct {
    order_id: OrderId,
    price: Price,
    quantity: Quantity,
};

const Trade = struct {
    bid_trade: TradeInfo,
    ask_trade: TradeInfo,
};

pub const Trades = std.ArrayList(Trade);

const ShardLocationInfo = struct {
    shard_index: usize,
    order: Order,
};

pub const PriceLevel = struct {
    total_volume: u64,
    order_count: usize,
};

fn PriceLevelMap(comptime side: Side) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        levels: std.AutoArrayHashMap(Price, PriceLevel),
        sorted_prices: std.ArrayList(Price),
        is_sorted: bool,
        side: Side,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .levels = std.AutoArrayHashMap(Price, PriceLevel).init(allocator),
                .sorted_prices = try std.ArrayList(Price).initCapacity(allocator, 1),
                .is_sorted = false,
                .side = side,
                .allocator = allocator,
            };
        }

        pub fn reserve(self: *Self, size: usize) !void {
            try self.levels.ensureTotalCapacity(size);
        }

        pub fn deinit(self: *Self) void {
            self.levels.deinit();
            self.sorted_prices.deinit();
        }

        pub fn get(self: *Self, price: Price) ?PriceLevel {
            return self.levels.get(price);
        }

        pub fn len(self: Self) usize {
            return self.levels.count();
        }

        pub fn getPtr(self: *Self, price: Price) ?*PriceLevel {
            return self.levels.getPtr(price);
        }

        pub fn remove(self: *Self, price: Price) bool {
            const removed = self.levels.swapRemove(price);
            if (removed) {
                self.is_sorted = false;
            }

            return removed;
        }

        pub fn iterator(self: *Self) std.AutoArrayHashMap(Price, PriceLevel).Iterator {
            return self.levels.iterator();
        }

        pub fn put(self: *Self, price: Price, level: PriceLevel) !void {
            try self.levels.put(price, level);
            self.is_sorted = false;
        }

        pub fn sort(self: *Self) !void {
            if (self.is_sorted) {
                return;
            }

            self.sorted_prices.clearRetainingCapacity();
            var it = self.levels.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.order_count > 0) {
                    try self.sorted_prices.append(self.allocator, entry.key_ptr.*);
                }
            }

            std.mem.sort(Price, self.sorted_prices.items, {}, std.sort.desc(Price));
            self.is_sorted = true;
        }

        pub fn getBestPrice(self: *Self) !?Price {
            try self.sort();

            if (self.sorted_prices.items.len == 0) {
                return null;
            }

            switch (self.side) {
                Side.Buy => {
                    return self.sorted_prices.items[0];
                },
                Side.Sell => {
                    return self.sorted_prices.items[self.sorted_prices.items.len - 1];
                },
            }
        }

        pub fn isEmpty(self: *Self) bool {
            return self.levels.count() == 0;
        }
    };
}

// const OrderBookLevelInfos = struct {
//     bids: PriceLevelMap(Side.Buy),
//     asks: PriceLevelMap(Side.Sell),
// };

const BookSnapshot = struct {
    bids: std.ArrayList(Order),
    asks: std.ArrayList(Order),
};

pub const OrderBook = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    shard_count: usize,

    bids: PriceLevelMap(Side.Buy),
    asks: PriceLevelMap(Side.Sell),
    orders: Orders,

    best_bid_cache: ?Price = null,
    best_ask_cache: ?Price = null,

    pub fn init(allocator: std.mem.Allocator, shard_count: usize) !Self {
        return .{
            .allocator = allocator,
            .bids = try PriceLevelMap(Side.Buy).init(allocator),
            .asks = try PriceLevelMap(Side.Sell).init(allocator),
            .orders = Orders.init(allocator),
            .shard_count = shard_count,
        };
    }

    pub fn getBestBid(self: *Self) ?Price {
        if (self.best_bid_cache) |price| {
            return price;
        }

        var best_bid: ?Price = null;
        // for (self.bids) |levels| {
        // var it = levels.iterator();
        var it = self.bids.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.order_count == 0) continue;
            best_bid = if (best_bid) |current_best|
                @max(current_best, entry.key_ptr.*)
            else
                entry.key_ptr.*;
        }
        // }
        self.best_bid_cache = best_bid;
        return best_bid;
    }

    pub fn getBestAsk(self: *Self) ?Price {
        if (self.best_ask_cache) |price| {
            return price;
        }

        var best_ask: ?Price = null;
        // for (self.asks) |levels| {
        //     var it = levels.iterator();
        var it = self.asks.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.order_count == 0) continue;
            best_ask = if (best_ask) |current_best|
                @max(current_best, entry.key_ptr.*)
            else
                entry.key_ptr.*;
        }
        // }
        self.best_ask_cache = best_ask;
        return best_ask;
    }

    fn getNextBid(self: *Self, current_price: Price) ?Price {
        var next_bid: ?Price = null;
        // for (self.bids) |levels| {
        // var it = levels.iterator();
        var it = self.bids.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.order_count == 0) continue;
            if (entry.key_ptr.* < current_price) {
                next_bid = if (next_bid) |current_next|
                    @max(current_next, entry.key_ptr.*)
                else
                    entry.key_ptr.*;
            }
        }
        // }
        return next_bid;
    }

    fn getNextAsk(self: *Self, current_price: Price) ?Price {
        var next_ask: ?Price = null;
        // for (self.bids) |levels| {
        // var it = levels.iterator();
        var it = self.asks.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.order_count == 0) continue;
            if (entry.key_ptr.* > current_price) {
                next_ask = if (next_ask) |current_next|
                    @max(current_next, entry.key_ptr.*)
                else
                    entry.key_ptr.*;
            }
        }
        // }
        return next_ask;
    }

    fn canMatch(self: *Self, side: Side, price: Price) !bool {
        switch (side) {
            Side.Buy => {
                if (self.asks.isEmpty()) {
                    return false;
                }

                const ask_price = (try self.asks.getBestPrice()).?;
                return price >= ask_price;
            },
            Side.Sell => {
                if (self.bids.isEmpty()) {
                    return false;
                }

                const bid_price = (try self.bids.getBestPrice()).?;
                return price <= bid_price;
            },
        }
    }

    fn getOrdersAtPrice(self: Self, side: Side, price: Price) !std.ArrayList(OrderEntry) {
        var orders = try std.ArrayList(OrderEntry).initCapacity(self.allocator, 1);
        var it = self.orders.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.price == price and entry.value_ptr.*.side != side) {
                try orders.append(
                    self.allocator,
                    .{
                        .key = .{
                            .price = price,
                            .id = entry.value_ptr.id,
                        },
                        .order = entry.value_ptr.*,
                    },
                );
            }
        }

        return orders;
    }

    // fn matchOrder(self: *Self, side: Side, price: Price, amount: Quantity) !Trades {
    fn matchOrder(self: *Self, order_to_match: Order) !Trades {
        var trades = try Trades.initCapacity(self.allocator, self.orders.count());
        const is_buy = order_to_match.side == Side.Buy;
        var best_price = if (is_buy) self.getBestAsk() else self.getBestBid();

        var remaining_amount = order_to_match.remaining_quantity;
        const price = order_to_match.price;
        const side = order_to_match.side;

        // TODO: Add SIMD batch operation (4 * bytes depending on architecture
        // const VECTOR_WIDTH = if (@import("builtin").cpu.arch == .x86_64) @as(usize, 4) else @as(usize, 2);
        //const BATCH_SIZE = VECTOR_WIDTH * 4;

        while (best_price != null and remaining_amount > 0) : (best_price = if (is_buy) self.getNextAsk(best_price.?) else self.getNextBid(best_price.?)) {
            if ((is_buy and best_price.? > price) or (!is_buy and best_price.? < price)) {
                break;
            }

            var orders = try self.getOrdersAtPrice(side, best_price.?);
            defer orders.deinit(self.allocator);
            std.log.debug("[DEBUG][Orderbook.matchOrder] orders_count: {},best_price: {any}, remaining_amount: {}, price: {}", .{ orders.items.len, best_price.?, remaining_amount, price });
            // TODO: SIMD
            // var batch_index: usize = 0;
            // while (batch_index + BATCH_SIZE <= orders.items.len) : (batch_index += BATCH_SIZE) {
            //    var batch_executed: u64 = 0;
            //    var j: usize = 0;
            //    while (j < BATCH_SIZE and remaining_amount > 0) : (j += VECTOR_WIDTH) {
            //        for (0..VECTOR_WIDTH) |k| {
            //            if (j + k < BATCH_SIZE) {

            if (orders.items.len == 0) {
                continue;
            }

            var j: usize = 0;
            while (j < orders.items.len) : (j += 1) {
                const matched_amount = orders.items[j].order.remaining_quantity;

                // if {
                //    remaining_amount = 2
                //    matched_amount = 5
                // } then {
                //    remaining_amount = 0
                //    fill_amount = 2
                //    is_fully_filled = false
                // }

                // if {
                //    remaining_amount = 20
                //    matched_amount = 5
                // } then {
                //    remaining_amount = 15
                //    fill_amount = 5
                //    is_fully_filled = true
                // }

                const fill_amount = @min(remaining_amount, matched_amount);
                const is_fully_filled = fill_amount == matched_amount;
                remaining_amount -= fill_amount;

                const order_count: i64 = if (is_fully_filled) -1 else 0;
                try self.updatePriceLevel(side, best_price.?, fill_amount, order_count);

                self.onOrderMatched(best_price.?, fill_amount, is_fully_filled);

                try trades.appendBounded(.{
                    .ask_trade = .{
                        .order_id = if (!is_buy) orders.items[j].order.id else order_to_match.id,
                        .quantity = fill_amount,
                        .price = best_price.?,
                    },
                    .bid_trade = .{
                        .order_id = if (is_buy) orders.items[j].order.id else order_to_match.id,
                        .quantity = fill_amount,
                        .price = best_price.?,
                    },
                });

                // Remove if filled or FillAndKill
                switch (order_to_match.order_type) {
                    .FillAndKill => {
                        _ = self.orders.swapRemove(.{ .id = order_to_match.id, .price = order_to_match.price });
                        try self.cancelOrder(order_to_match);
                    },
                    .GoodTillCancel => {
                        if (is_fully_filled) {
                            _ = self.orders.swapRemove(.{ .id = order_to_match.id, .price = order_to_match.price });
                        }
                    },
                }

                // self.onOrderMatched(bid.price, quantity, bid.isFilled());
                // self.onOrderMatched(ask.price, quantity, ask.isFilled());
                // var it = orders.iterator();
                // while (it.next()) |order_entry| {
                //     order_entry.value_ptr.*.fill(remaining_amount);
                //     // remaining_amount = order_entry.value_ptr.*.re
                //
                //
                // }
            }
        }

        return trades;
    }

    fn updatePriceLevel(self: *Self, side: Side, price: Price, volume_delta: Quantity, order_count_delta: i64) !void {
        const level_ptr = switch (side) {
            Side.Buy => self.asks.getPtr(price) orelse blk: {
                try self.asks.put(price, .{ .order_count = 0, .total_volume = 0 });
                break :blk self.asks.getPtr(price).?;
            },
            Side.Sell => self.bids.getPtr(price) orelse blk: {
                try self.bids.put(price, .{ .order_count = 0, .total_volume = 0 });
                break :blk self.bids.getPtr(price).?;
            },
        };

        level_ptr.total_volume = @max(0, level_ptr.total_volume + volume_delta);
        if (order_count_delta < 0) {
            level_ptr.order_count = @max(0, level_ptr.order_count - @as(usize, @intCast(@abs(order_count_delta))));
        } else {
            level_ptr.order_count = @max(0, level_ptr.order_count + @as(usize, @intCast(order_count_delta)));
        }

        switch (side) {
            Side.Buy => {
                if (level_ptr.order_count == 0) {
                    _ = self.asks.remove(price);
                }
                self.updateBestPrice(price, .Sell);
            },
            Side.Sell => {
                if (level_ptr.order_count == 0) {
                    _ = self.bids.remove(price);
                }
                self.updateBestPrice(price, .Buy);
            },
        }
    }

    fn updateBestPrice(self: *Self, price: Price, side: Side) void {
        switch (side) {
            Side.Buy => {
                self.best_bid_cache = if (self.best_bid_cache) |current_best| @max(current_best, price) else price;
            },

            Side.Sell => {
                self.best_ask_cache = if (self.best_ask_cache) |current_best| @max(current_best, price) else price;
            },
        }
    }

    // fn matchOrders(self: *Self) !Trades {
    //     const trades = try Trades.initCapacity(self.allocator, self.orders.count());
    //
    //     while (true) {
    //         if (self.bids.isEmpty() or self.asks.isEmpty()) {
    //             break;
    //         }
    //
    //         // const bid_price = self.bids.getBestPrice();
    //         // const ask_price = self.asks.getBestPrice();
    //         //
    //         // if (bid_price < ask_price) {
    //         //     break;
    //         // }
    //
    //         if (self.best_bid_cache.? < self.best_ask_cache.?) {
    //             break;
    //         }
    //
    //         const bid_price = self.best_bid_cache.?;
    //         const ask_price = self.best_ask_cache.?;
    //
    //         // We have a Match
    //
    //         const bids = &self.bids.get(bid_price).?;
    //         const asks = &self.asks.get(ask_price).?;
    //
    //         while (bids.len > 0 and asks.items.len > 0) {
    //             const bid = bids.items[0];
    //             const ask = asks.items[0];
    //
    //             const quantity = @min(bid.remaining_quantity, ask.remaining_quantity);
    //
    //             bid.fill(quantity);
    //             ask.fill(quantity);
    //
    //             if (bid.isFilled()) {
    //                 bids.pop();
    //                 self.orders.swapRemove(.{
    //                     .id = bid.id,
    //                     .price = bid_price,
    //                 });
    //             }
    //
    //             if (ask.isFilled()) {
    //                 asks.pop();
    //                 self.orders.swapRemove(.{
    //                     .id = ask.id,
    //                     .price = ask_price,
    //                 });
    //             }
    //
    //             trades.appendBounded(.{
    //                 .ask_trade = .{
    //                     .order_id = ask.id,
    //                     .quantity = quantity,
    //                     .price = ask.price,
    //                 },
    //                 .bid_price = .{
    //                     .order_id = bid.id,
    //                     .quantity = quantity,
    //                     .price = bid.price,
    //                 },
    //             });
    //
    //             self.onOrderMatched(bid.price, quantity, bid.isFilled());
    //             self.onOrderMatched(ask.price, quantity, ask.isFilled());
    //         }
    //
    //         if (0 == bids.items.len) {
    //             self.bids.remove(bid_price);
    //             _ = self.orders.swapRemove(.{ .price = bid_price });
    //         }
    //
    //         if (0 == asks.items.len) {
    //             self.asks.remove(ask_price);
    //             _ = self.orders.swapRemove(.{ .price = ask_price });
    //         }
    //     }
    //
    //     if (!self.bids.isEmpty()) {
    //         const bid_price = self.bids.getBestPrice();
    //         const bids = &self.bids.get(bid_price).?;
    //         if (bids.items.len > 0) {
    //             const order = bids.items[0].?;
    //             if (order.type == OrderType.FillAndKill) {
    //                 self.cancelOrder(order);
    //             }
    //         }
    //     }
    //
    //     if (!self.bids.isEmpty()) {
    //         const ask_price = self.asks.getBestPrice();
    //         const asks = &self.asks.get(ask_price).?;
    //         if (asks.items.len > 0) {
    //             const order = asks.items[0].?;
    //             if (order.type == OrderType.FillAndKill) {
    //                 self.cancelOrder(order);
    //             }
    //         }
    //     }
    //
    //     return trades;
    // }

    fn onOrderMatched(self: *Self, price: Price, quantity: Quantity, is_fully_filled: bool) void {
        _ = is_fully_filled; // autofix
        _ = quantity; // autofix
        _ = price; // autofix
        _ = self; // autofix
        // self.updateLevelData(price, quantity, is_fully_filled ? Action.Remove : Action.Match)
    }

    pub fn priceToShard(self: *Self, price: Price) usize {
        return @intCast(@mod(price, @as(i32, @intCast(self.shard_count))));
    }

    pub fn cancelOrder(self: *Self, order: Order) OrderError!void {
        if (null == self.orders.get(.{
            .id = order.id,
            .price = order.price,
        })) {
            return;
        }

        // _ = self.orders.swapRemove(.{
        //     .id = order.id,
        //     .price = order.price,
        // });

        switch (order.side) {
            Side.Buy => {
                const levels = &self.bids.getPtr(order.price).?;
                levels.*.order_count -= 1;
                levels.*.total_volume -= @as(u64, @intCast(order.getFilledQuantity()));
                // _ = levels.swapRemove();
            },
            Side.Sell => {
                const levels = &self.asks.getPtr(order.price).?;
                levels.*.order_count -= 1;
                levels.*.total_volume -= @as(u64, @intCast(order.getFilledQuantity()));
                // _ = levels.swapRemove();
            },
        }

        var it = self.orders.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.*.id == order.id) {
                // var o = entry.value_ptr.*;
                // const levels = switch (o.side) {
                //     Side.Buy => &self.bids,
                //     Side.Sell => &self.asks,
                // };
                // try self.updatePriceLevel(levels, o.price, -@as(i64, @intCast(o.price)), -1);

                // o.deinit(self.allocator);
                _ = self.orders.swapRemove(entry.key_ptr.*);
                return;
            }
        }

        return OrderError.OrderNotFound;
    }

    pub fn addOrder(self: *Self, order: Order) !Trades {
        const key: OrderKey = .{ .id = order.id, .price = order.price };
        if (self.orders.contains(key)) {
            return Trades{};
        }

        if (order.order_type == OrderType.FillAndKill and !try self.canMatch(order.side, order.price)) {
            return Trades{};
        }

        // const shard_index = self.priceToShard(order.price);

        // Update orders
        try self.orders.put(
            .{ .price = order.price, .id = order.id },
            order,
        );
        // if (self.orders.count() == 0) {
        //     std.log.debug("[DEBUG][Orderbook.addOrder] orders_count: {}", .{self.orders.count()});
        //     return OrderError.OutOfMemory;
        // }
        // if (self.orders.count() != 0) {
        //     std.log.debug("[DEBUG][Orderbook.addOrder] orders_count: {}", .{self.orders.count()});
        //     return OrderError.OutOfMemory;
        // }

        try self.updatePriceLevel(order.side, order.price, order.initial_quantity, 1);
        // Update price level
        // switch (order.side) {
        //     Side.Buy => {
        //         const levels = &self.bids.getPtr(order.price).?;
        //         levels.*.order_count += 1;
        //         levels.*.total_volume += order.initial_quantity;
        //         // try levels.put(key, order);
        //     },
        //     Side.Sell => {
        //         const levels = &self.asks.getPtr(order.price).?;
        //         levels.*.order_count += 1;
        //         levels.*.total_volume += order.initial_quantity;
        //     },
        // }

        // Update orders
        // try self.orders.put(
        //     .{ .price = order.price, .id = order.id },
        //     order,
        // );

        // update best price
        switch (order.side) {
            Side.Buy => {
                if (self.best_bid_cache) |best_bid| {
                    self.best_bid_cache = @max(best_bid, order.price);
                } else {
                    self.best_bid_cache = order.price;
                }
            },
            Side.Sell => {
                if (self.best_ask_cache) |best_ask| {
                    self.best_ask_cache = @max(best_ask, order.price);
                } else {
                    self.best_ask_cache = order.price;
                }
            },
        }

        return try self.matchOrder(order);
        // return try self.matchOrders();
    }

    pub fn modifyOrder(self: *Self, order: OrderModify) !Trades {
        const order_key: OrderKey = .{ .price = order.price, .id = order.id };
        if (!self.orders.contains(order_key)) {
            return;
        }

        const existing_order = &self.orders.get(order_key).?;

        self.cancelOrder(existing_order);
        return self.addOrder(order.toOrder(existing_order.side));
    }

    pub fn size(self: Self) usize {
        return self.orders.count();
    }

    pub fn snapshot(self: Self) !BookSnapshot {
        var bids = try std.ArrayList(Order).initCapacity(self.allocator, self.bids.len());
        var asks = try std.ArrayList(Order).initCapacity(self.allocator, self.asks.len());

        var it = self.orders.iterator();
        while (it.next()) |entry| {
            const order = entry.value_ptr.*;

            try switch (order.side) {
                .Buy => bids.append(self.allocator, order),
                .Sell => asks.append(self.allocator, order),
            };
        }

        // Sort bids by price descending (highest first)
        std.mem.sort(Order, bids.items, {}, struct {
            fn lessThan(_: void, a: Order, b: Order) bool {
                return a.price > b.price;
            }
        }.lessThan);

        // Sort asks by price ascending (lowest first)
        std.mem.sort(Order, asks.items, {}, struct {
            fn lessThan(_: void, a: Order, b: Order) bool {
                return a.price < b.price;
            }
        }.lessThan);

        return BookSnapshot{
            .bids = bids,
            .asks = asks,
        };
    }

    // pub fn updateLevelData(self: *Self, price: Price, quantity: Quantity, level_data: Action) void {
    //
    // }

};
