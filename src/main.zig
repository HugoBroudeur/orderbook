const std = @import("std");
const root = @import("root");
const orderbook = @import("orderbook.zig");

pub fn seedOrderbook(allocator: std.mem.Allocator) !orderbook.OrderBook {
    var book = try orderbook.OrderBook.init(allocator, 1);

    var trades = try std.ArrayList(orderbook.Trades).initCapacity(allocator, 10);

    try trades.append(allocator, try book.addOrder(orderbook.Order.init(1, .GoodTillCancel, .Buy, 10, 1)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(2, .GoodTillCancel, .Buy, 11, 3)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(3, .GoodTillCancel, .Buy, 9, 10)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(4, .GoodTillCancel, .Sell, 12, 10)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(5, .GoodTillCancel, .Sell, 10, 10)));
    // _ = try book.addOrder(order);

    std.log.debug("[DEBUG][main.seedOrderbook] Trades made: {any}", .{trades});
    std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[4].items});

    return book;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const book = try seedOrderbook(allocator);
    const stats = book.snapshot();

    std.log.debug("[DEBUG][main] Orderbook: size {}", .{book.size()});
    std.log.debug("[DEBUG][main] Stats: {any}", .{stats});

    // Prints to stderr, ignoring potential errors.
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // try orderbook.main();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };

    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
