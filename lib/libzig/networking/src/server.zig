const std = @import("std");
const socket = @import("socket.zig");
const networking = @import("main.zig");

pub const Handler = struct {
    name: []const u8,
    handler_fn: *const fn ([]const u8, std.mem.Allocator) anyerror![]u8,
};

pub const ServerContext = struct { ip: []const u8, port: u16, max_threads_count: usize, max_client_connections: usize };

pub const TcpServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    address: std.net.Address,

    socket: socket.TcpSocket,
    // thread_pool: *std.Thread.Pool,
    max_threads_count: usize,
    is_started: bool,
    log_level: networking.LogLevel,
    client_sockets: std.ArrayList(*socket.ClientSocket),
    polls: [4096]std.posix.pollfd = undefined,

    pub fn init(allocator: std.mem.Allocator, ctx: ServerContext) !Self {
        const address = try std.net.Address.resolveIp(ctx.ip, ctx.port);
        // var pool: std.Thread.Pool = undefined;
        // try pool.init(.{ .allocator = allocator, .n_jobs = ctx.max_threads_count });
        // std.log.info("{any}", .{pool});

        return .{
            .allocator = allocator,
            .address = address,
            .socket = socket.TcpSocket.init(address.any.family),
            // .thread_pool = &pool,
            .max_threads_count = ctx.max_threads_count,
            .is_started = false,
            .log_level = .Debug,
            .client_sockets = try std.ArrayList(*socket.ClientSocket).initCapacity(allocator, ctx.max_client_connections),
        };
    }

    pub fn deinit(self: *Self) void {
        // self.thread_pool.deinit();
        self.socket.deinit();
    }

    pub fn start(self: *Self) !void {
        if (self.is_started) {
            return networking.ServerError.NotStarted;
        }

        std.log.debug("[DEBUG][TcpServer.start] Starting server", .{});

        try self.socket.open();
        try self.socket.listen(&self.address);

        const poll: std.posix.pollfd = .{
            .fd = self.socket.listener.?,
            .events = std.posix.POLL.IN,
            .revents = 0,
        };
        self.polls[0] = poll;
        self.is_started = true;

        if (self.log_level == .Debug) {
            std.log.debug("[DEBUG][TcpServer.start] Server started on {f}", .{self.address.in});
        }
    }

    pub fn listen(self: *Self) !void {
        if (self.log_level == .Debug) {
            std.log.debug("[DEBUG][TcpServer.listen] Server listening", .{});
        }

        var pool: std.Thread.Pool = undefined;
        try pool.init(.{ .allocator = self.allocator, .n_jobs = self.max_threads_count });
        defer pool.deinit();

        while (true) {
            const client = socket.ClientSocket.wait_for_client(self.socket) catch |err| {
                std.log.err("[ERROR][TcpServer.listen] Error ClientSocket Wait for Client: {}", .{err});
                continue;
            };

            // try self.thread_pool.spawn(socket.ClientSocket.handle, .{client});
            try pool.spawn(socket.ClientSocket.handle, .{client});
        }
    }

    // fn poll(self: *Self) !void {
    //     for (self.client_sockets) |connection| {
    //         const n =
    //         if (connection) |socket| {
    //         }
    //     }
    // }
};

pub const GrpcServer = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,

    socket: socket.TcpSocket,
    // server: std.net.StreamServer,

    handlers: std.ArrayList(Handler),

    is_started: bool,
    log_level: networking.LogLevel,

    pub fn init(allocator: std.mem.Allocator, ip: []const u8, port: u16) !GrpcServer {
        const address = try std.net.Address.resolveIp(ip, port);
        return .{
            .allocator = allocator,
            .address = address,
            .socket = socket.TcpSocket.init(address.any.family),
            .is_started = false,
            .log_level = .Debug,
        };
    }

    pub fn deinit(self: *GrpcServer) void {
        self.handlers.deinit();
        // self.server.deinit();
        self.socket.deinit();
        // self.health_check.deinit();
    }

    pub fn start(self: *GrpcServer) !void {
        if (self.is_started) {
            return networking.ServerError.NotStarted;
        }

        try self.server.listen(self.address);
        try self.health_check.setStatus("grpc.health.v1.Health", .SERVING);
        std.log.info("Server listening on {}", .{self.address});

        while (true) {
            const connection = try self.server.accept();
            try self.handleConnection(connection);
        }

        std.log.debug("[DEBUG][TcpServer.start] Starting server", .{});

        try self.socket.open();
        try self.socket.listen(&self.address);

        self.is_started = true;

        if (self.log_level == .Debug) {
            std.log.debug("[DEBUG][TcpServer.start] Server started on {f}", .{self.address.in});
        }
    }
};

// pub const GrpcServera = struct {
//     allocator: std.mem.Allocator,
//     address: std.net.Address,
//
//     server: std.net.StreamServer,
//     handlers: std.ArrayList(Handler),
//     // compression: compression.Compression,
//     // auth: auth.Auth,
//     // health_check: health.HealthCheck,
//
//     pub fn init(allocator: std.mem.Allocator, port: u16, secret_key: []const u8) !GrpcServer {
//         const address = try std.net.Address.parseIp("127.0.0.1", port);
//         return GrpcServer{
//             .allocator = allocator,
//             .address = address,
//             .server = std.net.StreamServer.init(.{}),
//             .handlers = std.ArrayList(Handler).init(allocator),
//             // .compression = compression.Compression.init(allocator),
//             // .auth = auth.Auth.init(allocator, secret_key),
//             // .health_check = health.HealthCheck.init(allocator),
//         };
//     }
//
//     pub fn deinit(self: *GrpcServer) void {
//         self.handlers.deinit();
//         self.server.deinit();
//         self.health_check.deinit();
//     }
//
//     pub fn start(self: *GrpcServer) !void {
//         try self.server.listen(self.address);
//         try self.health_check.setStatus("grpc.health.v1.Health", .SERVING);
//         std.log.info("Server listening on {}", .{self.address});
//
//         while (true) {
//             const connection = try self.server.accept();
//             try self.handleConnection(connection);
//         }
//     }
//
//     fn handleConnection(self: *GrpcServer, conn: std.net.StreamServer.Connection) !void {
//         var trans = try transport.Transport.init(self.allocator, conn.stream);
//         defer trans.deinit();
//
//         // Setup streaming
//         var message_stream = streaming.MessageStream.init(self.allocator, 1024);
//         defer message_stream.deinit();
//
//         while (true) {
//             const message = trans.readMessage() catch |err| switch (err) {
//                 error.ConnectionClosed => break,
//                 else => return err,
//             };
//
//             // Verify auth token from headers
//             try self.auth.verifyToken(message.headers.get("authorization") orelse "");
//
//             // Decompress if needed
//             const decompressed = try self.compression.decompress(
//                 message.data,
//                 message.compression_algorithm,
//             );
//             defer self.allocator.free(decompressed);
//
//             // Process message
//             for (self.handlers.items) |handler| {
//                 const response = try handler.handler_fn(decompressed, self.allocator);
//                 defer self.allocator.free(response);
//
//                 // Compress response
//                 const compressed = try self.compression.compress(
//                     response,
//                     message.compression_algorithm,
//                 );
//                 defer self.allocator.free(compressed);
//
//                 try trans.writeMessage(compressed);
//             }
//         }
//     }
// };
