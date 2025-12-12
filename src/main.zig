const std = @import("std");
const networking = @import("networking");
const env = @import("config.zig");
const game = @import("game/game.zig");

// const sokol = @import("sokol");
// const slog = sokol.log;
// const sapp = sokol.app;

const WINDOW_WIDTH = 1920;
const WINDOW_HEIGHT = 1060;

// pub fn seedOrderbook(allocator: std.mem.Allocator) !OrderBook {
//     var book = try OrderBook.init(allocator, 1);
//
//     var trades = try std.ArrayList(OrderBook.Trades).initCapacity(allocator, 10);
//     defer trades.deinit(allocator);
//
//     try trades.append(allocator, try book.addOrder(OrderBook.Order.init(1, .GoodTillCancel, .Buy, 10, 1)));
//     try trades.append(allocator, try book.addOrder(OrderBook.Order.init(2, .GoodTillCancel, .Buy, 11, 3)));
//     try trades.append(allocator, try book.addOrder(OrderBook.Order.init(3, .GoodTillCancel, .Buy, 9, 10)));
//     try trades.append(allocator, try book.addOrder(OrderBook.Order.init(4, .GoodTillCancel, .Buy, 13, 10)));
//     try trades.append(allocator, try book.addOrder(OrderBook.Order.init(5, .GoodTillCancel, .Sell, 12, 10)));
//     try trades.append(allocator, try book.addOrder(OrderBook.Order.init(6, .GoodTillCancel, .Sell, 10, 10)));
//     // try trades.append(allocator, try book.addOrder(orderbook.Order.init(6, .GoodTillCancel, .Sell, 7, 10)));
//     // _ = try book.addOrder(order);
//
//     std.log.debug("[DEBUG][main.seedOrderbook] Trades made: {any}", .{trades});
//     std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[4].items});
//     // std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[5].items});
//     // std.log.debug("[DEBUG][main.seedOrderbook] Trades made on the sell: {any}", .{trades.items[4].items});
//
//     return book;
// }

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    const allocator = arena.allocator();

    const config = env.init();

    // var book = try seedOrderbook(allocator);
    // defer book.deinit();
    // const stats = book.snapshot();
    //
    // std.log.debug("[DEBUG][main] Orderbook: size {}", .{book.size()});
    // std.log.debug("[DEBUG][main] Stats: {any}", .{stats});

    var tcp_server = try networking.server.TcpServer.init(allocator, .{
        .ip = "127.0.0.1",
        .port = 3000,
        .max_threads_count = config.http_max_threads_count,
        .max_client_connections = 4096,
    });
    defer tcp_server.deinit();

    // try game.start(allocator);

    try game.init(
        allocator,
        config,
    );

    game.run();

    // sapp.run(.{
    //     .init_cb = init,
    //     .frame_cb = frame,
    //     .cleanup_cb = cleanup,
    //     .event_cb = event,
    //     .window_title = "Price is Power",
    //     .width = WINDOW_WIDTH,
    //     .height = WINDOW_HEIGHT,
    //     .icon = .{ .sokol_default = true },
    //     .logger = .{ .func = slog.func },
    // });
    // try tcp_server.start();
    // try tcp_server.listen();

    // var grpc_server = try networking.grpc.TcpServer.init(allocator, "127.0.0.1", 3000);
    // var grpc_server = try networking.grpc.OrderbookServiceImpl.Subscribe(self: *OrderbookServiceImpl, request: SubscribeRequest)
    // defer grpc_server.deinit();
    // try grpc_server.start();
    // try grpc_server.listen();
    // Prints to stderr, ignoring potential errors.
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // try orderbook.main();
}

// export fn init() void {
//     game.setup();
//     // game.setup() catch |err| {
//     //     std.log.err("[ERROR][main] Init: {}", .{err});
//     //     sapp.quit();
//     //     // game.shutdown();
//     // };
// }
//
// export fn frame() void {
//     game.frame();
// }
//
// export fn cleanup() void {
//     game.shutdown();
// }
//
// export fn event(ev: [*c]const sapp.Event) void {
//     game.handleEvent(ev);
// }
