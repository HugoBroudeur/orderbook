const std = @import("std");
const Serde = @import("serde");

const World = @import("../ecs/world.zig");

/// Bridges any Serde-serializable type into knoedel's
/// registerComponentCodec/registerResourceCodec shape. Length-prefixed so
/// multiple values can sit back-to-back on one stream (Serde's fromReader
/// reads-to-EOF and errors on trailing bytes, so it can't do this alone).
pub fn SerdeCodec(comptime T: type) type {
    return struct {
        pub fn serialize(value: *const T, w: *std.Io.Writer) anyerror!void {
            var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
            defer aw.deinit();
            try Serde.json.toWriter(&aw.writer, value.*);
            const bytes = aw.writer.buffered();
            try w.writeInt(u32, @intCast(bytes.len), .little);
            try w.writeAll(bytes);
        }

        pub fn deserialize(out: *T, allocator: std.mem.Allocator, r: *std.Io.Reader) anyerror!void {
            const len = try r.takeInt(u32, .little);
            out.* = try Serde.json.fromSlice(T, allocator, try r.take(len));
        }
    };
}
