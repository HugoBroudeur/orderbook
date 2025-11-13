const std = @import("std");

/// A UUID is 128 bits long, and can guarantee uniqueness across space and time (RFC4122).
pub const Uuid = u128;

/// Switch between little and big endian
fn switchU48(v: u48) u48 {
    return ((v >> 40) & 0x0000000000ff) | ((v >> 24) & 0x00000000ff00) | ((v >> 8) & 0x000000ff0000) | ((v << 8) & 0x0000ff000000) | ((v << 24) & 0x00ff00000000) | ((v << 40) & 0xff0000000000);
}

const rand = std.crypto.random;
const time = std.time;

/// Create a time-based version 7 UUID
///
/// This UUID features a time-ordered value field derived
/// from the widely implemented and well known Unix Epoch
/// timestamp source (# of milliseconds since midnight
/// 1 Jan 1970 UTC - leap seconds excluded).
///
/// Implementations SHOULD utilize this UUID over
/// version 1 and 6 if possible.
fn new2(r: std.Random, millis: *const fn () i64) Uuid {
    //   0                   1                   2                   3
    //   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    //  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //  |                           unix_ts_ms                          |
    //  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //  |          unix_ts_ms           |  var  |       rand_a          |
    //  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //  |var|                        rand_b                             |
    //  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    //  |                            rand_b                             |
    //  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

    // Get milliseconds since 1 Jan 1970 UTC
    const tms = @as(u48, @intCast(millis() & 0xffffffffffff));
    // Fill everything after the timestamp with random bytes
    var uuid: Uuid = @as(Uuid, @intCast(r.int(u80))) << 48;
    // Encode tms in big endian and OR it to the uuid
    uuid |= @as(Uuid, @intCast(switchU48(tms)));
    // Set variant and version field
    // * variant - top two bits are 1, 0
    // * version - top four bits are 0, 1, 1, 1
    uuid &= 0xffffffffffffff3fff0fffffffffffff;
    uuid |= 0x00000000000000800070000000000000;
    return uuid;
}

pub fn new() Uuid {
    return new2(rand, time.milliTimestamp);
}
