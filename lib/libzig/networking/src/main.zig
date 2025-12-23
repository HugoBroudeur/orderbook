pub const server = @import("server.zig");
pub const socket = @import("socket.zig");
pub const client = @import("client.zig");
pub const grpc = @import("grpc_impl.zig");

pub const LogLevel = enum {
    Debug,
    Info,
};

pub const ServerError = error{
    NotStarted,
};

pub const SocketError = error{
    AlreadyOpen,
    NotOpen,
    Closed,
    BufferTooSmall,
};
