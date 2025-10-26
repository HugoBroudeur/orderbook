const std = @import("std");

pub const SocketError = error{
    NotOpen,
};

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

    const tpe: usize = std.posix.SOCK.STREAM;
    const protocol: usize = std.posix.IPPROTO.TCP;

    domain: u32,
    listener: ?std.posix.socket_t = null,

    pub fn init(domain: u32) Self {
        return .{ .domain = domain };
    }

    pub fn open(self: *Self) !void {
        if (null == self.listener) {
            self.listener = try std.posix.socket(self.domain, tpe, protocol);
        }
    }

    pub fn deinit(self: Self) void {
        std.posix.close(self.listener.?);
    }

    pub fn accept(self: *Self, client_address: *std.net.Address, client_address_len: ?*std.posix.socklen_t) !i32 {
        if (null != self.listener) {
            return try std.posix.accept(self.listener.?, &client_address.any, client_address_len, 0);
        }
        return SocketError.NotOpen;
    }
};
