const std = @import("std");
const socket = @import("socket.zig");

pub const ServerError = error{
    ClientConnectionClosed,
};

pub const TcpServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    address: std.net.Address,

    socket: socket.TcpSocket,
    is_started: bool,

    pub fn init(allocator: std.mem.Allocator, ip: []const u8, port: u16) !Self {
        const address = try std.net.Address.resolveIp(ip, port);
        return .{
            .allocator = allocator,
            .address = address,
            .socket = socket.TcpSocket.init(address.any.family),
            .is_started = false,
        };
    }

    pub fn deinit(self: Self) void {
        self.socket.deinit();
    }

    pub fn start(self: *Self) !void {
        if (!self.is_started) {
            std.log.debug("[DEBUG][TcpServer.start] Starting server", .{});
            try self.socket.open();

            try std.posix.setsockopt(self.socket.listener.?, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
            try std.posix.bind(self.socket.listener.?, &self.address.any, self.address.getOsSockLen());
            try std.posix.listen(self.socket.listener.?, 128);

            std.log.debug("[DEBUG][TcpServer.start] Server started on {f}", .{self.address.in});
            self.is_started = true;
        }
    }

    pub fn listen(self: *Self) void {
        std.log.debug("[DEBUG][TcpServer.start] Server listening", .{});
        while (true) {
            var client_address: std.net.Address = undefined;
            var client_address_len: std.posix.socklen_t = @sizeOf(std.net.Address);

            const client_socket = self.socket.accept(&client_address, &client_address_len) catch |err| {
                std.log.err("[ERROR][TcpServer.listen] Error while accepting client data: {}", .{err});
                continue;
            };
            defer std.posix.close(client_socket);

            std.debug.print("{f} connected\n", .{client_address});

            write(client_socket, "Hello (and goodbye)") catch |err| {
                std.log.err("[ERROR][TcpServer.listen] Error while writting client data: {}", .{err});
            };
        }
    }

    fn write(client_socket: std.posix.socket_t, msg: []const u8) !void {
        var pos: usize = 0;
        while (pos < msg.len) {
            const written = try std.posix.write(client_socket, msg[pos..]);
            if (written == 0) {
                return ServerError.ClientConnectionClosed;
            }
            pos += written;
        }
    }
};
