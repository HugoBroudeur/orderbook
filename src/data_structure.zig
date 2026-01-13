const std = @import("std");
const assert = std.debug.assert;

pub fn DynamicBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        buffer: std.ArrayList(T),
        size: usize,
        cur_pos: usize = 0,

        pub fn init(allocator: std.mem.Allocator, comptime size: usize) !Self {
            return .{
                .allocator = allocator,
                .size = size,
                .buffer = try .initCapacity(allocator, size),
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit(self.allocator);
        }

        pub fn reset(self: *Self) void {
            self.buffer.clearRetainingCapacity();
            self.cur_pos = 0;
        }

        pub fn rewind(self: *Self, to: usize) void {
            if (to >= self.cur_pos) return;
            if (self.cur_pos == 0) return;
            @memset(self.buffer.items[to .. self.cur_pos - 1], undefined);
            self.buffer.items.len = to;
            self.cur_pos = @intCast(to);
        }

        pub fn push(self: *Self, el: T) void {
            assert(self.cur_pos + 1 <= self.size);

            self.buffer.appendBounded(el) catch unreachable;
            self.cur_pos += 1;
        }

        pub fn pushSlice(self: *Self, els: []T) void {
            assert(self.cur_pos + els.len <= self.size);

            self.buffer.appendSliceBounded(els) catch unreachable;
            self.cur_pos += els.len;
        }

        pub fn getRemainingSlot(self: *Self) usize {
            return self.size - self.cur_pos;
        }

        // TODO?: This O(n)
        // pub fn remove(self: *Self, el: T) void {
        //     var index: usize = null;
        //     for (self.stack[0..self.cur_pos], 0..) |e, i| {
        //         if (e == el) {
        //             assert(self.cur_pos - 1 >= 0);
        //             self.stack[i] = undefined;
        //             self.cur_pos -= 1;
        //             break;
        //         }
        //     }
        //
        //     if (index != null) {
        //
        //     }
        // }

        pub fn pop(self: *Self) void {
            if (self.buffer.pop() != null) {
                self.cur_pos -= 1;
            }
        }

        pub fn sizeInBytes(self: *Self) usize {
            return self.buffer.items[0..self.cur_pos].len * @sizeOf(T);
        }

        pub fn getSlice(self: *Self) []T {
            return self.buffer.items[0..self.cur_pos];
        }
    };
}
