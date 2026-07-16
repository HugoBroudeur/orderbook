const std = @import("std");
const zm = @import("zmath");

const Resource = @import("../resource_management/resource.zig");

const SceneGraph = @import("graph.zig").SceneGraph;

// TODO: Move those 2 to a better architecture
const MaterialInstance = @import("../engine/graphics/materials.zig").MaterialInstance;
const SkyboxInstance = @import("../engine/graphics/skybox.zig").CubemapInstance;

const Buffer = @import("../engine/vulkan/buffer.zig");
const Bounds = @import("../resource_management/mesh.zig").Bounds;

const Sampler = @import("../engine/vulkan/sampler.zig");
const AllocatedImage = @import("../engine/vulkan/image.zig").AllocatedImage;
const Engine = @import("../engine/vulkan/engine.zig");

pub const RenderObject = struct {
    index_count: u32,
    first_index: u32,
    index_buffer: Buffer,

    vertex_buffer: Buffer,
    vertex_buffer_offset: u64 = 0,

    material: *MaterialInstance,

    transform: zm.Mat,
    bounds: Bounds = .{},

    pub fn isVisible(self: *const RenderObject, viewproj: zm.Mat) bool {
        // Build model-view-projection:
        // mul(A,B) applies A first then B, so this is: model → view → proj.
        const matrix = zm.mul(self.transform, viewproj);

        var clip_min = zm.f32x4(1.5, 1.5, 1.5, 0.0);
        var clip_max = zm.f32x4(-1.5, -1.5, -1.5, 0.0);

        // 8 corners of a unit cube scaled and offset by the AABB.
        const corners = [8][3]f32{
            .{ 1, 1, 1 },  .{ 1, 1, -1 },  .{ 1, -1, 1 },  .{ 1, -1, -1 },
            .{ -1, 1, 1 }, .{ -1, 1, -1 }, .{ -1, -1, 1 }, .{ -1, -1, -1 },
        };

        for (corners) |s| {
            const wx = self.bounds.origin[0] + s[0] * self.bounds.extents[0];
            const wy = self.bounds.origin[1] + s[1] * self.bounds.extents[1];
            const wz = self.bounds.origin[2] + s[2] * self.bounds.extents[2];

            // Row-vector * matrix = clip-space position.
            const clip = zm.mul(zm.f32x4(wx, wy, wz, 1.0), matrix);
            const w = clip[3];
            // Perspective divide into NDC.
            const ndc = zm.f32x4(clip[0] / w, clip[1] / w, clip[2] / w, 0.0);

            clip_min = @min(clip_min, ndc);
            clip_max = @max(clip_max, ndc);
        }

        // Vulkan NDC: x ∈ [-1,1], y ∈ [-1,1], z ∈ [0,1]
        if (clip_min[2] > 1.0 or clip_max[2] < 0.0 or
            clip_min[0] > 1.0 or clip_max[0] < -1.0 or
            clip_min[1] > 1.0 or clip_max[1] < -1.0)
        {
            return false;
        }
        return true;
    }
};

pub const Node = struct {
    pub const NodeKind = union(enum) {
        basic: void,
        mesh: *Resource.Mesh,
    };

    allocator: std.mem.Allocator,
    parent_node: ?*Node = null,
    child_nodes: std.ArrayList(*Node) = .empty,

    local_transform: zm.Mat = zm.identity(),
    world_transform: zm.Mat = zm.identity(),

    kind: NodeKind,

    pub fn init(allocator: std.mem.Allocator, kind: NodeKind) Node {
        return .{
            .allocator = allocator,
            .kind = kind,
        };
    }

    pub fn refreshTransform(self: *Node, parent_matrix: zm.Mat) void {
        self.world_transform = zm.mul(self.local_transform, parent_matrix);
        for (self.child_nodes.items) |child| child.refreshTransform(self.world_transform);
    }

    pub fn draw(self: *Node, top_matrix: *zm.Mat, graph: *SceneGraph) !void {
        switch (self.kind) {
            .mesh => |mesh| {
                const node_matrix = zm.mul(top_matrix.*, self.world_transform);

                for (mesh.surfaces.items) |surface| {
                    // No material bound (glTF without any materials): skip
                    // rather than crash — there is nothing valid to draw with.
                    const material = surface.material orelse continue;
                    const ro: RenderObject = .{
                        .index_count = @intCast(surface.count),
                        .first_index = @intCast(surface.start_index),
                        .index_buffer = mesh.buffers.index,
                        .vertex_buffer = mesh.buffers.vertex,
                        .material = &material.data,
                        .transform = node_matrix,
                        .bounds = surface.bounds,
                    };
                    const list = switch (ro.material.pass_type) {
                        .Transparent => &graph.transparent_surfaces,
                        else => &graph.opaque_surfaces,
                    };
                    try list.append(self.allocator, ro);
                }
            },
            else => {},
        }

        for (self.child_nodes.items) |child| try child.draw(top_matrix, graph);
    }

    pub fn deinit(self: *Node) void {
        self.child_nodes.deinit(self.allocator);
        self.parent_node = null;
        switch (self.kind) {
            .mesh => |*m| m.mesh = null,
            else => {},
        }
    }
};

pub const Model = struct {
    allocator: std.mem.Allocator,

    // storage for all the data on a given glTF file
    meshes: std.array_hash_map.String(*Resource.Mesh),

    /// Owns the memory
    nodes: std.array_hash_map.String(*Node),
    textures: std.array_hash_map.String(*Resource.Texture),
    materials: std.array_hash_map.String(*Resource.Material),

    // nodes that dont have a parent, for iterating through the file in tree order
    top_nodes: std.ArrayList(*Node),

    creator: *Engine = undefined,

    pub fn init(allocator: std.mem.Allocator) !Model {
        return .{
            .allocator = allocator,
            .top_nodes = try .initCapacity(allocator, 0),
            .meshes = .empty,
            .nodes = .empty,
            .textures = .empty,
            .materials = .empty,
        };
    }

    pub fn draw(self: *Model, top_matrix: *zm.Mat, graph: *SceneGraph) !void {
        for (self.top_nodes.items) |node| {
            try node.draw(top_matrix, graph);
        }
    }

    pub fn deinit(self: *Model) void {
        self.textures.deinit(self.allocator);

        self.meshes.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.materials.deinit(self.allocator);
        self.top_nodes.deinit(self.allocator);
    }
};

pub const SkyboxObject = struct {
    index_count: u32,
    first_index: u32,
    index_buffer: Buffer,

    vertex_buffer: Buffer,
    vertex_buffer_offset: u64 = 0,

    skybox: *SkyboxInstance,

    transform: zm.Mat,
};
