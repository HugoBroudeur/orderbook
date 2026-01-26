// The mesh assume indice u16,

const std = @import("std");
const vk = @import("vulkan");
const sdl = @import("sdl3");
const zm = @import("zmath");

const Buffer = @import("buffer.zig");
const CommandPool = @import("command_pool.zig");
const Image = @import("image.zig");
const Data = @import("../data.zig");
const GraphicsContext = @import("../../core/graphics_context.zig");

const Mesh = @This();

pub const MeshBuffers = struct {
    index: ?Buffer = null,
    vertex: ?Buffer = null,
};

pub const PushConstants2D = struct {
    scale: Data.Scale2D,
    translate: Data.Translate2D,
    // vb_address: vk.Buffer = undefined,
};

pub const PushConstants3D = struct {
    world_matrix: Data.WorldMatrix3D,
    // vb_address: vk.Buffer = undefined,
};
pub const PushConstantType = enum { two_d, three_d };

pub const PushConstants = union(PushConstantType) {
    two_d: PushConstants2D,
    three_d: PushConstants3D,
};

// allocator: std.mem.Allocator,

image: ?Image = null,

buffers: MeshBuffers = .{},
constants: ?PushConstants = null,

pub fn init() Mesh {
    return .{};
}

// Helper Creation function for a Quad Mesh
pub fn makeQuadMesh(ctx: *const GraphicsContext, cmd_pool: *const CommandPool, vertices: [4]Data.Quad.Vertex, indices: [6]Data.Quad.Indice) !Mesh {
    var mesh = Mesh.init();

    try mesh.setVertices(ctx, cmd_pool, &std.mem.toBytes(vertices));
    try mesh.setIndices(ctx, cmd_pool, &indices);

    return mesh;
}

// Helper Creation function for a Quad Mesh
pub fn makeTriangleMesh(ctx: *const GraphicsContext, cmd_pool: *const CommandPool, vertices: [3]Data.Quad.Vertex) !Mesh {
    var mesh = Mesh.init();

    try mesh.setVertices(ctx, cmd_pool, &std.mem.toBytes(vertices));

    return mesh;
}

pub fn setVertices(self: *Mesh, ctx: *const GraphicsContext, cmd_pool: *const CommandPool, vertices: []const u8) !void {
    self.buffers.vertex = try Buffer.create(ctx, @intCast(vertices.len), .{
        .storage_buffer_bit = true,
        .transfer_dst_bit = true,
        .shader_device_address_bit = true,
    }, .{ .device_local_bit = true });
    try self.buffers.vertex.?.fastTransfer(ctx, cmd_pool, vertices);
}

pub fn setIndices(self: *Mesh, ctx: *const GraphicsContext, cmd_pool: *const CommandPool, indices: []Data.Indice) !void {
    self.buffers.index = try Buffer.create(ctx, indices.len, .{
        .index_buffer_bit = true,
        .transfer_dst_bit = true,
    }, .{ .device_local_bit = true });
    try self.buffers.index.?.fastTransfer(ctx, cmd_pool, indices);
}

pub fn setImage(self: *Mesh, image: Image) void {
    self.image = image;
}

pub fn setPushConstants(self: *Mesh, constants: PushConstants) !void {
    self.constants = constants;
}

pub fn destroy(self: *Mesh, ctx: *const GraphicsContext) void {
    if (self.buffers.vertex) |*vb| {
        vb.destroy(ctx);
    }
    if (self.buffers.index) |*vi| {
        vi.destroy(ctx);
    }
    if (self.image) |*image| {
        image.destroy(ctx);
    }
}
