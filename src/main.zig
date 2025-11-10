const std = @import("std");
const orderbook = @import("orderbook.zig");
const networking = @import("networking");
const env = @import("config.zig");

pub fn seedOrderbook(allocator: std.mem.Allocator) !orderbook.OrderBook {
    var book = try orderbook.OrderBook.init(allocator, 1);

    var trades = try std.ArrayList(orderbook.Trades).initCapacity(allocator, 10);
    defer trades.deinit(allocator);

    try trades.append(allocator, try book.addOrder(orderbook.Order.init(1, .GoodTillCancel, .Buy, 10, 1)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(2, .GoodTillCancel, .Buy, 11, 3)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(3, .GoodTillCancel, .Buy, 9, 10)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(4, .GoodTillCancel, .Buy, 13, 10)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(5, .GoodTillCancel, .Sell, 12, 10)));
    try trades.append(allocator, try book.addOrder(orderbook.Order.init(6, .GoodTillCancel, .Sell, 10, 10)));
    // try trades.append(allocator, try book.addOrder(orderbook.Order.init(6, .GoodTillCancel, .Sell, 7, 10)));
    // _ = try book.addOrder(order);

    std.log.debug("[DEBUG][main.seedOrderbook] Trades made: {any}", .{trades});
    std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[4].items});
    // std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[5].items});
    // std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[4].items});

    return book;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const config = env.init();

    var book = try seedOrderbook(allocator);
    defer book.deinit();
    const stats = book.snapshot();

    std.log.debug("[DEBUG][main] Orderbook: size {}", .{book.size()});
    std.log.debug("[DEBUG][main] Stats: {any}", .{stats});

    var tcp_server = try networking.server.TcpServer.init(allocator, .{
        .ip = "127.0.0.1",
        .port = 3000,
        .max_threads_count = config.http_max_threads_count,
    });
    defer tcp_server.deinit();
    try tcp_server.start();
    try tcp_server.listen();

    // var grpc_server = try networking.grpc.TcpServer.init(allocator, "127.0.0.1", 3000);
    // var grpc_server = try networking.grpc.OrderbookServiceImpl.Subscribe(self: *OrderbookServiceImpl, request: SubscribeRequest)
    // defer grpc_server.deinit();
    // try grpc_server.start();
    // try grpc_server.listen();
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
