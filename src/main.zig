const std = @import("std");
const networking = @import("networking");
const env = @import("config.zig");
const App = @import("core/app.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

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

    const config = env.init(init.environ_map);

    // var tcp_server = try networking.server.TcpServer.init(allocator, io, .{
    //     .ip = "127.0.0.1",
    //     .port = 3000,
    //     .max_threads_count = config.http_max_threads_count,
    //     .max_client_connections = 4096,
    // });
    // defer tcp_server.deinit();

    var app: App = .{
        .allocator = allocator,
        .io = io,
        .layer_stack = .init(),
    };
    try app.init(config);

    app.run();
}

test {
    _ = @import("core/app.zig");
    _ = @import("data_structure.zig");
    _ = @import("engine/vulkan/mesh.zig");
}
