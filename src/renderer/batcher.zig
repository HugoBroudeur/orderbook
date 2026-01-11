// Implementation for a 2D Batcher for Quads

const std = @import("std");

pub const Quad = @import("data.zig").Quad;
pub const DataStructure = @import("../data_structure.zig");

pub const BATCH_SIZE_QUADS: u32 = 10000;
pub const BATCH_SIZE_VERTICES: u32 = BATCH_SIZE_QUADS * Quad.VERTEX_COUNT;
pub const BATCH_SIZE_INDICES: u32 = BATCH_SIZE_QUADS * Quad.INDEX_COUNT;

pub const Batcher = @This();

// vb: [BATCH_SIZE_VERTICES]Quad.Vertex,
allocator: std.mem.Allocator,
indices: std.ArrayList(Quad.Indice),
vertices: DataStructure.DynamicBuffer(Quad.Vertex),
// vi: DataStructure.Stack(Quad.Indice, BATCH_SIZE_INDICES),

pub fn init(allocator: std.mem.Allocator) !Batcher {
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
        .indices = list,
        .vertices = try .init(allocator, BATCH_SIZE_VERTICES),
    };
}

pub fn deinit(self: *Batcher) void {
    self.indices.deinit(self.allocator);
    self.vertices.deinit();
}

pub fn getMaxVerticesCount(self: *Batcher) usize {
    return self.vertices.size;
}

pub fn getMaxIndicesCount(self: *Batcher) usize {
    return self.indices.capacity;
}

pub fn begin(self: *Batcher) void {
    self.vertices.reset();
}
pub fn end(self: *Batcher) void {
    _ = self;
}

pub fn flush(self: *Batcher) void {
    _ = self;
}
