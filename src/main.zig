const std = @import("std");
const networking = @import("networking");
const env = @import("config.zig");
const app = @import("core/app.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // var gpa = std.heap.DebugAllocator(.{
    //     .safety = true, // Enable safety checks
    //     // .thread_safe = true, // Thread safety
    //     .verbose_log = true, // Set true for detailed logs
    // }){};
    // defer {
    //     const leaked = gpa.deinit();
    //     if (leaked == .leak) {
    //         std.debug.print("MEMORY LEAK DETECTED!\n", .{});
    //     }
    // }
    // const allocator = gpa.allocator();

    // var tracy_allocator: tracy.Allocator = .{ .parent = arena.allocator() };
    // const allocator = tracy_allocator.allocator();

    const config = env.init();

    var tcp_server = try networking.server.TcpServer.init(allocator, .{
        .ip = "127.0.0.1",
        .port = 3000,
        .max_threads_count = config.http_max_threads_count,
        .max_client_connections = 4096,
    });
    defer tcp_server.deinit();

    try app.init(
        allocator,
        config,
    );

    app.run();
}
