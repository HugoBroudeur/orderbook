const std = @import("std");

pub const TestTcpClient = struct {
    const Self = @This();
    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn connect(address: std.net.Address, port: u16) !void {
        _ = address;
        _ = port;
        // try std.posix.setsockopt(listener, posix.sol.socket, posix.so.reuseaddr, &std.mem.tobytes(@as(c_int, 1)));
        // try std.posix.bind(listener, &address.any, address.getOsSockLen());
        // try std.posix.listen(listener, 128);
    }
};
