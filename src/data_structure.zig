const std = @import("std");
const assert = std.debug.assert;

pub fn DynamicBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        buffer: std.ArrayList(T),
        size: usize,
        cur_pos: u32 = 0,

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

        pub fn push(self: *Self, el: T) bool {
            assert(self.cur_pos + 1 <= self.size);

            self.buffer.appendBounded(el) catch unreachable;
            self.cur_pos += 1;
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
    };
}
