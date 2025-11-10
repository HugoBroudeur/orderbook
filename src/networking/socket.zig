const std = @import("std");
const networking = @import("mod.zig");

const BACKLOG = 128;

pub const UdpSocket = struct {
    const Self = @This();
    const tpe: std.posix.SOCK = std.posix.SOCK.DGRAM;
    const protocol: std.posix.IPPROTO = std.posix.IPPROTO.UDP;
    listener: ?std.posix.socket_t,

    pub fn init(domain: u32) Self {
        return .{ .listener = try std.posix.socket(domain, tpe, protocol) };
    }
    pub fn deinit(self: Self) void {
        std.posix.close(self.listener);
    }
};

pub const TcpSocket = struct {
    const Self = @This();

    const tpe: usize = std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK;
    const protocol: usize = std.posix.IPPROTO.TCP;

    domain: u32,
    listener: ?std.posix.socket_t = null,

    pub fn init(domain: u32) Self {
        return .{ .domain = domain };
    }

    pub fn open(self: *Self) !void {
        if (null != self.listener) {
            return networking.SocketError.AlreadyOpen;
        }
        self.listener = try std.posix.socket(self.domain, tpe, protocol);
    }

    pub fn listen(self: *Self, address: *std.net.Address) !void {
        if (null == self.listener) {
            return networking.SocketError.NotOpen;
        }
        try std.posix.setsockopt(self.listener.?, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try std.posix.bind(self.listener.?, &address.any, address.getOsSockLen());
        try std.posix.listen(self.listener.?, BACKLOG);
    }

    pub fn deinit(self: Self) void {
        std.posix.close(self.listener.?);
    }
};

pub const ClientSocket = struct {
    const Self = @This();

    socket: std.posix.socket_t = undefined,
    address: std.net.Address = undefined,
    address_len: std.posix.socklen_t = undefined,
    log_level: networking.LogLevel = .Debug,
    buffer: [BACKLOG]u8 = undefined,

    const flags = std.posix.SOCK.NONBLOCK;

    pub fn wait_for_client(server_socket: TcpSocket) !Self {
        if (null == server_socket.listener) {
            return networking.SocketError.NotOpen;
        }
        var address: std.net.Address = undefined;
        var address_len: std.posix.socklen_t = @sizeOf(std.net.Address);
        const socket = try std.posix.accept(server_socket.listener.?, &address.any, &address_len, flags);

        std.log.debug("[DEBUG][ClientSocket.wait_for_client] Client connected ({f})", .{address});

        return .{
            .socket = socket,
            .address = address,
            .address_len = address_len,
            .log_level = .Debug,
            .buffer = @splat(0),
        };
    }

    pub fn close(self: *Self) void {
        std.posix.close(self.socket);

        if (self.log_level == .Debug) {
            std.log.debug("[DEBUG][ClientSocket.close] Goodbye client {f}", .{self.address});
        }

        self.socket = undefined;
        self.address = undefined;
        self.address_len = undefined;
    }

    pub fn handle(self: ClientSocket) void {
        self._handle() catch |err| {
            std.log.err("[ERROR][TcpServer.listen] Error while handling client: {}", .{err});
        };
    }

    fn _handle(self: Self) !void {
        defer @constCast(&self).close();

        // Set read timeout
        const timeout: std.posix.timeval = .{ .sec = 2, .usec = 500000 };
        try std.posix.setsockopt(self.socket, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));

        // const msg = try self.readMessage();
        const msg = "Hello mate";

        // Set write timeout
        try std.posix.setsockopt(self.socket, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));
        try self.writeMessage(msg);
    }

    fn readMessage(self: Self) ![]u8 {
        var header: [4]u8 = undefined;
        try self.readAll(&header);

        const len = std.mem.readInt(u32, &header, .little);
        if (self.log_level == .Debug) {
            std.log.debug("[DEBUG][ClientSocket.readMessage] Header {s}, length {}", .{ header, len });
        }

        if (len > self.buffer.len) {
            return networking.SocketError.BufferTooSmall;
        }

        try self.readAll(&self.buffer);
        return self.buffer[0..len];
    }

    fn readAll(self: Self, buf: []u8) !void {
        var into = buf;
        while (into.len > 0) {
            const n = try std.posix.read(self.socket, into);
            if (n == 0) {
                return networking.SocketError.Closed;
            }
            into = into[n..];
        }
    }

    fn writeMessage(self: Self, msg: []const u8) !void {
        var buf: [4]u8 = undefined;
        // Prefix all messages with a 4 bytes number as the lenght of the message
        std.mem.writeInt(u32, &buf, @intCast(msg.len), .little);

        if (self.log_level == .Debug) {
            std.log.debug("[DEBUG][ClientSocket.writeMessage] Message size: {}, Content: {s}", .{ std.mem.readInt(u32, &buf, .little), msg });
        }
        var simd_vec = [2]std.posix.iovec_const{
            .{ .len = buf.len, .base = &buf },
            .{ .len = msg.len, .base = msg.ptr },
        };

        // Send actual message
        try self.writeSimd(&simd_vec);
        // try self.writeAll(&buf);
        //
        // try self.writeAll(msg);
    }

    fn writeSimd(self: Self, vec: []std.posix.iovec_const) !void {
        var i: usize = 0;
        while (true) {
            var n = try std.posix.writev(self.socket, vec[i..]);
            while (n >= vec[i].len) {
                n -= vec[i].len;
                i += 1;
                if (i >= vec.len) return;
            }

            vec[i].base += n;
            vec[i].len -= n;
        }
    }

    fn writeAll(self: Self, msg: []const u8) !void {
        var pos: usize = 0;
        while (pos < msg.len) {
            const written = try std.posix.write(self.socket, msg[pos..]);
            if (written == 0) {
                return networking.SocketError.Closed;
            }
            pos += written;
        }
    }
};

pub const Reader = struct {
    buf: []u8,

    pos: usize = 0,
    start: usize = 0,
    socket: *ClientSocket,

    header_len: usize = 4,

    pub fn init(socket: *ClientSocket, header_len: usize) Reader {
        return .{
            .header_len = header_len,
            .socket = socket,
        };
    }

    pub fn readMessage(self: *Reader) ![]u8 {
        var buf = self.buf;

        while (true) {
            if (try self.bufferedMessage()) |msg| {
                return msg;
            }

            const pos = self.pos;
            const n = try std.posix.read(self.socket.socket, buf[pos..]);
            if (n == 0) {
                return networking.SocketError.Closed;
            }

            self.pos += pos + n;
        }
    }

    fn bufferedMessage(self: *Reader) !?[]u8 {
        const buf = self.buf;
        const pos = self.pos;
        const start = self.start;

        std.debug.assert(pos >= start);

        const unprocessed = buf[start..pos];

        if (unprocessed.len < self.header_len) {
            self.ensureSpace(self.header_len - unprocessed.len) catch unreachable;
            return null;
        }

        const msg_len = std.mem.readInt(u32, unprocessed[0..self.header_len], .little);
        const total_len = self.header_len + msg_len;
        if (unprocessed.len < total_len) {
            try self.ensureSpace(total_len);
            return null;
        }

        self.start += total_len;
        return unprocessed[self.header_len..total_len];
    }

    fn ensureSpace(self: *Reader, requested_space: usize) networking.SocketError!void {
        const buf = self.buf;
        if (buf.len < requested_space) {
            return networking.SocketError.BufferTooSmall;
        }

        const start = self.start;
        const space_left = buf.len - start;
        if (space_left >= requested_space) {
            return;
        }

        // Compacting the buffer back to the beginning
        const unprocessed = buf[start..self.pos];
        @memmove(buf[0..unprocessed.len], unprocessed);
        self.start = 0;
        self.pos = unprocessed.len;
    }
};
