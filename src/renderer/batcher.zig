// Implementation for a 2D Batcher for Quads

const std = @import("std");
const assert = std.debug.assert;

const Quad = @import("data.zig").Quad;
const Logger = @import("../log.zig").MaxLogs(50);
const Cmd = @import("command.zig");

const DataStructure = @import("../data_structure.zig");

pub const MAX_BATCHES: usize = 10; // Probably needs to be equal to the CPU count ?
pub const BATCH_SIZE_QUADS: u32 = 10000;
pub const BATCH_SIZE_VERTICES: u32 = BATCH_SIZE_QUADS * Quad.VERTEX_COUNT;
pub const BATCH_SIZE_INDICES: u32 = BATCH_SIZE_QUADS * Quad.INDEX_COUNT;

const Batcher = @This();

pub const Batch = struct {
    allocator: std.mem.Allocator,
    size: usize,

    indices: std.ArrayList(Quad.Indice),
    vertices: DataStructure.DynamicBuffer(Quad.Vertex),

    cur_indices: u32 = 0,
    cur_instances: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, comptime size: usize) !Batch {
        var offset: Quad.Indice = 0;
        var i: usize = 0;
        var indices: [BATCH_SIZE_INDICES]Quad.Indice = @splat(0);
        while (i < BATCH_SIZE_INDICES) : (i += Quad.INDEX_COUNT) {
            // 1st Triangle
            indices[0 + i] = 0 + offset;
            indices[1 + i] = 1 + offset;
            indices[2 + i] = 2 + offset;

            // 2nd Triangle
            indices[3 + i] = 2 + offset;
            indices[4 + i] = 3 + offset;
            indices[5 + i] = 0 + offset;

            offset += Quad.VERTEX_COUNT;
        }
        var list: std.ArrayList(Quad.Indice) = try .initCapacity(allocator, BATCH_SIZE_INDICES);
        for (indices) |index| {
            list.appendAssumeCapacity(index);
        }

        return .{
            .allocator = allocator,
            .size = size,
            .indices = list,
            .vertices = try .init(allocator, size * Quad.VERTEX_COUNT),
        };
    }

    pub fn deinit(self: *Batch) void {
        self.indices.deinit(self.allocator);
        self.vertices.deinit();
    }

    pub fn clear(self: *Batch) void {
        self.cur_indices = 0;
        self.cur_instances = 0;
        self.vertices.reset();
    }

    // Assume we only add quads
    pub fn add(self: *Batch, vertices: []Quad.Vertex) void {
        assert(self.vertices.getRemainingSlot() >= vertices.len);
        assert(self.cur_indices + 6 <= BATCH_SIZE_INDICES);

        self.vertices.pushSlice(vertices);
        self.cur_indices += 6;
        self.cur_instances += 2;
    }

    pub fn hasSpaceFor(self: *Batch, size: u32) bool {
        return self.vertices.getRemainingSlot() >= size;
    }

    pub fn toBytes(self: *Batch) struct { vertices: []const u8, indices: []const u8 } {
        return .{
            .vertices = std.mem.sliceAsBytes(self.vertices.getSlice()),
            .indices = std.mem.sliceAsBytes(self.indices.items[0..self.cur_indices]),
        };

        // return std.mem.sliceAsBytes(self.vertices.getSlice()) ++ std.mem.sliceAsBytes(self.indices.items[0..self.cur_indices]);
    }
};

allocator: std.mem.Allocator,

batching: bool = false,
batches: std.ArrayList(Batch),
pool_size: usize,

// Reference of the current batch index being batched
cur_batch: usize = 0,

pub fn init(allocator: std.mem.Allocator) !Batcher {
    var batches: [MAX_BATCHES]Batch = @splat(undefined);
    var i: usize = 0;
    while (i < MAX_BATCHES) : (i += 1) {
        batches[i] = try Batch.init(allocator, BATCH_SIZE_QUADS);
    }
    var list: std.ArrayList(Batch) = try .initCapacity(allocator, MAX_BATCHES);
    for (batches) |batch| {
        list.appendAssumeCapacity(batch);
    }

    return .{
        .allocator = allocator,
        .batches = list,
        .pool_size = MAX_BATCHES,
    };
}

pub fn deinit(self: *Batcher) void {
    self.batches.deinit(self.allocator);
}

pub fn getVertexBufferSizeInBytes(self: *Batcher) u32 {
    _ = self;
    return BATCH_SIZE_QUADS * Quad.VERTEX_COUNT * @sizeOf(Quad.Vertex);
}

pub fn getIndexBufferSizeInBytes(self: *Batcher) u32 {
    _ = self;
    return BATCH_SIZE_QUADS * Quad.INDEX_COUNT * @sizeOf(Quad.Indice);
}

pub fn getTransferBufferSizeInBytes(self: *Batcher) u32 {
    return self.getVertexBufferSizeInBytes() + self.getIndexBufferSizeInBytes();
}

pub fn begin(self: *Batcher) void {
    self.batching = true;
    var i: u32 = 0;
    while (i <= self.cur_batch) : (i += 1) {
        self.batches.items[i].clear();
    }
    self.cur_batch = 0;
}
pub fn end(self: *Batcher) []Batch {
    assert(self.batching);
    Logger.info("[Batcher.end] Current Batch: {}", .{self.cur_batch});

    self.batching = false;

    // Key points about Zig slicing:
    //
    // Syntax is array[start..end] where end is exclusive
    // [0..0] = empty slice (length 0)
    // [0..1] = one element (just index 0)
    // [0..2] = two elements (indices 0 and 1)
    // [0..n] = first n elements
    return self.batches.items[0 .. self.cur_batch + 1];
}

pub fn shouldFlush(self: *Batcher, cmd: Cmd.DrawCmd) bool {
    const vertices_count: u32 = switch (cmd) {
        // assume all cmd require 4 vertices
        else => 4,
    };

    return !self.batches.items[self.cur_batch].hasSpaceFor(vertices_count);
}

pub fn flush(self: *Batcher) void {
    std.log.debug("[Batcher.flush] flushing Batch {} [{}/{} vertices]", .{ self.cur_batch, self.batches.items[self.cur_batch].vertices.cur_pos, self.batches.items[self.cur_batch].vertices.size });
    assert(self.batching);
    assert(self.cur_batch < self.pool_size);

    self.cur_batch += 1;
}

pub fn push(self: *Batcher, _draw_cmd: Cmd.DrawCmd) void {
    assert(self.batching);
    var draw_cmd = _draw_cmd;
    var batch = &self.batches.items[self.cur_batch];
    switch (draw_cmd) {
        .quad => |*cmd| {
            var vertices: [4]Quad.Vertex = .{
                .{ .pos = .{ cmd.p1.x, cmd.p1.y }, .uv = .{ 0, 0 }, .col = cmd.color.toVec4() },
                .{ .pos = .{ cmd.p2.x, cmd.p2.y }, .uv = .{ 1, 0 }, .col = cmd.color.toVec4() },
                .{ .pos = .{ cmd.p3.x, cmd.p3.y }, .uv = .{ 1, 1 }, .col = cmd.color.toVec4() },
                .{ .pos = .{ cmd.p4.x, cmd.p4.y }, .uv = .{ 0, 1 }, .col = cmd.color.toVec4() },
            };

            batch.add(&vertices);
        },
        .quad_fill => |*cmd| {
            var vertices: [4]Quad.Vertex = .{
                .{ .pos = .{ cmd.p1.x, cmd.p1.y }, .uv = .{ 0, 0 }, .col = cmd.color1.toVec4() },
                .{ .pos = .{ cmd.p2.x, cmd.p2.y }, .uv = .{ 1, 0 }, .col = cmd.color2.toVec4() },
                .{ .pos = .{ cmd.p3.x, cmd.p3.y }, .uv = .{ 1, 1 }, .col = cmd.color3.toVec4() },
                .{ .pos = .{ cmd.p4.x, cmd.p4.y }, .uv = .{ 0, 1 }, .col = cmd.color4.toVec4() },
            };

            batch.add(&vertices);
        },

        .quad_img => {},
        else => unreachable,
    }
}
