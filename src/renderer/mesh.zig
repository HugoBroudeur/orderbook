// The mesh assume indice u16,

const std = @import("std");
const sdl = @import("sdl3");

const Quad = @import("data.zig").Quad;
const DataStructure = @import("../data_structure.zig");

pub const MeshType = enum { _2d, _3d };
pub fn Mesh(comptime VertexType: anytype) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        indices: std.ArrayList(u16),
        vertices: std.ArrayList(VertexType),

        pub fn init(allocator: std.mem.Allocator, vertices: []VertexType, indices: []u16) Mesh {
            var indice_list: std.ArrayList(u16) = try .initCapacity(allocator, indices.len);
            for (indices) |index| {
                indice_list.appendAssumeCapacity(index);
            }

            var vertice_list: std.ArrayList(VertexType) = try .initCapacity(allocator, vertices.len);
            for (vertices) |vertice| {
                vertice_list.appendAssumeCapacity(vertice);
            }

            return .{
                .allocator = allocator,
                .indices = indice_list,
                .vertices = vertice_list,
            };
        }

        pub fn deinit(self: *Self) void {
            self.indices.deinit(self.allocator);
            self.vertices.deinit(self.allocator);
        }

        pub fn getIndicesCount(self: *Self) usize {
            return self.indices.capacity;
        }

        pub fn getVerticesCount(self: *Self) usize {
            return self.vertices.capacity;
        }
    };
}
