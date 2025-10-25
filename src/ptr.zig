const std = @import("std");

pub fn SharedPtr(comptime T: type) type {
    return struct {
        const Self = @This();
        ref_count: *std.atomic.Value(usize),
        ptr: *T,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, value: T) !Self {
            const self = try allocator.create(Self);

            self.* = .{
                .ref_count = try allocator.create(std.atomic.Value(usize)),
                .ptr = try allocator.create(T),
                .allocator = allocator,
            };

            self.ref_count.* = std.atomic.Value(usize).init(1);
            self.ptr.* = value;

            return self;
        }

        pub fn clone(self: *Self) *Self {
            _ = self.ref_count.fetchAdd(1, .seq_cst);
            return self;
        }

        pub fn get(self: *Self) *T {
            return self.ptr;
        }

        pub fn deinit(self: *Self) void {
            if (self.ref_count.fetchSub(1, .seq_cst) <= 1) {
                self.allocator.destroy(self.ptr);
                self.allocator.destroy(self.ref_count);
                self.allocator.destroy(self);
            }
        }
    };
}
