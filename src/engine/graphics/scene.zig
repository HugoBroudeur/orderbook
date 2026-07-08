const std = @import("std");
const log = std.log.scoped(.graphics);
const assert = std.debug.assert;
const zm = @import("zmath");

const materials = @import("materials.zig");
const objects = @import("objects.zig");
const Mesh = @import("../vulkan/mesh.zig");
const Sampler = @import("../vulkan/sampler.zig");
const Buffer = @import("../vulkan/buffer.zig");
const Image = @import("../vulkan/image.zig");
const Descriptor = @import("../vulkan/descriptor.zig");
const Engine = @import("../vulkan/engine.zig");
const Uuid = @import("uuid");

pub const BasicNode = struct {
    allocator: std.mem.Allocator,
    parent_node: ?*IRenderable = null,
    child_nodes: std.ArrayList(*IRenderable),

    local_transform: zm.Mat = zm.identity(),
    world_transform: zm.Mat = zm.identity(),

    pub fn init(allocator: std.mem.Allocator) !BasicNode {
        return .{
            .allocator = allocator,
            .child_nodes = try .initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *BasicNode) void {
        self.parent_node = null;
        self.child_nodes.deinit(self.allocator);
    }

    pub fn children(self: *BasicNode) *std.ArrayList(*IRenderable) {
        return &self.child_nodes;
    }

    pub fn getParent(self: *BasicNode) ?*IRenderable {
        return self.parent_node;
    }

    pub fn setParent(self: *BasicNode, parent: ?*IRenderable) void {
        self.parent_node = parent;
    }

    pub fn refreshTransform(self: *BasicNode, parent_matrix: zm.Mat) void {
        self.world_transform = zm.mul(self.local_transform, parent_matrix);
        for (self.child_nodes.items) |child| {
            child.refreshTransform(self.world_transform);
        }
    }

    pub fn draw(self: *BasicNode, top_matrix: *zm.Mat, ctx: *DrawContext) !void {
        for (self.child_nodes.items) |child| {
            try child.draw(top_matrix, ctx);
        }
    }

    pub fn interface(self: *BasicNode) IRenderable {
        return IRenderable.interface(self);
    }
};

pub const MeshNode = struct {
    allocator: std.mem.Allocator,
    parent_node: ?*IRenderable = null,
    child_nodes: std.ArrayList(*IRenderable),

    local_transform: zm.Mat = zm.identity(),
    world_transform: zm.Mat = zm.identity(),

    mesh: ?*Mesh = null,

    pub fn init(allocator: std.mem.Allocator) !MeshNode {
        return .{
            .allocator = allocator,
            .child_nodes = try .initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *MeshNode) void {
        self.parent_node = null;
        self.mesh = null;
        self.child_nodes.deinit(self.allocator);
    }

    pub fn getParent(self: *MeshNode) ?*IRenderable {
        return self.parent_node;
    }

    pub fn setParent(self: *MeshNode, parent: ?*IRenderable) void {
        self.parent_node = parent;
    }

    pub fn children(self: *MeshNode) *std.ArrayList(*IRenderable) {
        return &self.child_nodes;
    }

    pub fn refreshTransform(self: *MeshNode, parent_matrix: zm.Mat) void {
        self.world_transform = zm.mul(self.local_transform, parent_matrix);
        for (self.child_nodes.items) |child| {
            child.refreshTransform(self.world_transform);
        }
    }

    pub fn draw(self: *MeshNode, top_matrix: *zm.Mat, ctx: *DrawContext) !void {
        const node_matrix = zm.mul(top_matrix.*, self.world_transform);

        if (self.mesh) |m| {
            for (m.surfaces.items) |surface| {
                if (m.buffers.index != null and m.buffers.vertex != null) {
                    const ro: objects.RenderObject = .{
                        .index_count = @intCast(surface.count),
                        .first_index = @intCast(surface.start_index),
                        .index_buffer = m.buffers.index.?,
                        .vertex_buffer = m.buffers.vertex.?,
                        .material = &surface.material.?.data,
                        .transform = node_matrix,
                        .bounds = surface.bounds,
                    };
                    const list = switch (ro.material.pass_type) {
                        .Transparent => &ctx.transparent_surfaces,
                        else => &ctx.opaque_surfaces,
                    };
                    try list.append(self.allocator, ro);
                }
            }
        }

        for (self.child_nodes.items) |child| {
            try child.draw(top_matrix, ctx);
        }
    }

    pub fn interface(self: *MeshNode) IRenderable {
        return IRenderable.interface(self);
    }
};

pub const LoadedGLTF = struct {
    allocator: std.mem.Allocator,

    // storage for all the data on a given glTF file
    meshes: std.array_hash_map.String(*Mesh),
    nodes: std.array_hash_map.String(*IRenderable),
    images: std.array_hash_map.String(*Image),
    materials: std.array_hash_map.String(*Mesh.GLTFMaterial),

    // nodes that dont have a parent, for iterating through the file in tree order
    top_nodes: std.ArrayList(*IRenderable),
    samplers: std.ArrayList(Sampler),

    descriptor_pool: Descriptor.DescriptorAllocator = undefined,
    /// Owned by this LoadedGLTF: the bindless cache (engine.buffer_cache)
    /// only holds the raw vk handle, so this must be destroyed here.
    material_data_buffer: Buffer = undefined,

    material_data_buffer_slot_idx: u32 = undefined,
    creator: *Engine = undefined,

    pub fn interface(self: *LoadedGLTF) IRenderable {
        return IRenderable.interface(self);
    }

    pub fn init(allocator: std.mem.Allocator) !LoadedGLTF {
        return .{
            .allocator = allocator,
            .samplers = try .initCapacity(allocator, 0),
            .top_nodes = try .initCapacity(allocator, 0),
            .meshes = .empty,
            .nodes = .empty,
            .images = .empty,
            .materials = .empty,
        };
    }

    pub fn draw(self: *LoadedGLTF, top_matrix: *zm.Mat, ctx: *DrawContext) !void {
        for (self.top_nodes.items) |node| {
            try node.draw(top_matrix, ctx);
        }
    }

    pub fn deinit(self: *LoadedGLTF) void {
        const ctx = self.creator.ctx;

        for (self.samplers.items) |*s| s.destroy(ctx);
        self.samplers.deinit(self.allocator);
        self.images.deinit(self.allocator);

        self.material_data_buffer.destroy(ctx);
        // descriptor_pool is never initialized anymore (creation commented
        // out in asset/manager.zig) — destroying it would touch undefined memory.
        // self.descriptor_pool.destroy(ctx);

        self.meshes.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.materials.deinit(self.allocator);
        self.top_nodes.deinit(self.allocator);
    }
};

pub const DrawContext = struct {
    pub const QueueType = enum {
        opaque_surface,
        transparent_surface,
    };

    allocator: std.mem.Allocator,
    opaque_surfaces: std.ArrayList(objects.RenderObject),
    transparent_surfaces: std.ArrayList(objects.RenderObject),

    _opaque_sufaces_sorted: std.ArrayList(u64),

    pub fn init(allocator: std.mem.Allocator) DrawContext {
        return .{
            .allocator = allocator,
            .opaque_surfaces = .empty,
            .transparent_surfaces = .empty,
            ._opaque_sufaces_sorted = .empty,
        };
    }

    /// knoedel resource contract: a resource's deinit must accept the world
    /// allocator. DrawContext frees with its own stored allocator, so the
    /// parameter is unused — but the signature must match or resource
    /// registration fails to compile.
    pub fn deinit(self: *DrawContext, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.opaque_surfaces.deinit(self.allocator);
        self.transparent_surfaces.deinit(self.allocator);
        self._opaque_sufaces_sorted.deinit(self.allocator);
    }

    pub fn reset(self: *DrawContext) void {
        self.opaque_surfaces.clearRetainingCapacity();
        self.transparent_surfaces.clearRetainingCapacity();
        self._opaque_sufaces_sorted.clearRetainingCapacity();
    }

    // Sort the opaque_surfaces by materials and index buffers for reusing the same buffers when rendering
    pub fn sort(self: *DrawContext) void {
        const SortCtx = struct {
            draw_ctx: *DrawContext,

            pub fn lessThan(ctx: @This(), a: u64, b: u64) bool {
                const roa = &ctx.draw_ctx.opaque_surfaces.items[a];
                const rob = &ctx.draw_ctx.opaque_surfaces.items[b];
                if (@intFromPtr(roa.material) == @intFromPtr(rob.material)) {
                    return @intFromPtr(&roa.index_buffer) < @intFromPtr(&rob.index_buffer);
                }
                return @intFromPtr(roa.material) < @intFromPtr(rob.material);
            }
        };

        std.mem.sort(u64, self._opaque_sufaces_sorted.items, SortCtx{ .draw_ctx = self }, SortCtx.lessThan);
    }

    pub fn frustumCulling(self: *DrawContext, scene_view_proj: zm.Mat) !void {
        self._opaque_sufaces_sorted.clearRetainingCapacity();
        try self._opaque_sufaces_sorted.ensureTotalCapacity(self.allocator, self.opaque_surfaces.items.len);

        for (self.opaque_surfaces.items, 0..) |*ro, i| {
            if (ro.isVisible(scene_view_proj)) {
                self._opaque_sufaces_sorted.appendAssumeCapacity(i);
            }
        }
    }
};

pub const IRenderable = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        setParent: *const fn (*anyopaque, ?*IRenderable) void,
        getParent: *const fn (*anyopaque) ?*IRenderable,
        refreshTransform: *const fn (*anyopaque, parent_matrix: zm.Mat) void,
        children: *const fn (*anyopaque) *std.ArrayList(*IRenderable),
        draw: *const fn (*anyopaque, top_matrix: *zm.Mat, ctx: *DrawContext) anyerror!void,
    };

    pub fn refreshTransform(self: *IRenderable, parent_matrix: zm.Mat) void {
        return self.vtable.refreshTransform(self.ptr, parent_matrix);
    }

    pub fn getParent(self: *IRenderable) ?*IRenderable {
        return self.vtable.getParent(self.ptr);
    }

    pub fn setParent(self: *IRenderable, parent: ?*IRenderable) void {
        return self.vtable.setParent(self.ptr, parent);
    }

    pub fn children(self: *IRenderable) *std.ArrayList(*IRenderable) {
        return self.vtable.children(self.ptr);
    }

    pub fn draw(self: *IRenderable, top_matrix: *zm.Mat, ctx: *DrawContext) !void {
        return self.vtable.draw(self.ptr, top_matrix, ctx);
    }

    pub fn interface(ptr: anytype) IRenderable {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn getParent(impl: *anyopaque) ?*IRenderable {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.getParent(self);
            }
            fn setParent(impl: *anyopaque, parent: ?*IRenderable) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.setParent(self, parent);
            }
            fn refreshTransform(impl: *anyopaque, parent_matrix: zm.Mat) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.refreshTransform(self, parent_matrix);
            }
            fn children(impl: *anyopaque) *std.ArrayList(*IRenderable) {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.children(self);
            }
            fn draw(impl: *anyopaque, top_matrix: *zm.Mat, ctx: *DrawContext) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.draw(self, top_matrix, ctx);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .getParent = Impl.getParent,
                .setParent = Impl.setParent,
                .refreshTransform = Impl.refreshTransform,
                .children = Impl.children,
                .draw = Impl.draw,
            },
        };
    }
};
