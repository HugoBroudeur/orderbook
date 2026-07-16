const std = @import("std");
const zm = @import("zmath");
const log = std.log.scoped(.scene_graph);

const Objects = @import("objects.zig");

pub const SceneGraph = struct {
    pub const QueueType = enum {
        opaque_surface,
        transparent_surface,
    };

    allocator: std.mem.Allocator,
    opaque_surfaces: std.ArrayList(Objects.RenderObject),
    transparent_surfaces: std.ArrayList(Objects.RenderObject),
    skybox: ?Objects.SkyboxObject,

    _opaque_sufaces_sorted: std.ArrayList(u64),

    pub fn init(allocator: std.mem.Allocator) SceneGraph {
        return .{
            .allocator = allocator,
            .opaque_surfaces = .empty,
            .transparent_surfaces = .empty,
            ._opaque_sufaces_sorted = .empty,
            .skybox = null,
        };
    }

    /// knoedel resource contract: a resource's deinit must accept the world
    /// allocator. DrawContext frees with its own stored allocator, so the
    /// parameter is unused — but the signature must match or resource
    /// registration fails to compile.
    pub fn deinit(self: *SceneGraph, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.opaque_surfaces.deinit(self.allocator);
        self.transparent_surfaces.deinit(self.allocator);
        self._opaque_sufaces_sorted.deinit(self.allocator);
    }

    pub fn reset(self: *SceneGraph) void {
        self.opaque_surfaces.clearRetainingCapacity();
        self.transparent_surfaces.clearRetainingCapacity();
        self._opaque_sufaces_sorted.clearRetainingCapacity();
    }

    // Sort the opaque_surfaces by materials and index buffers for reusing the same buffers when rendering
    pub fn sort(self: *SceneGraph) void {
        const SortCtx = struct {
            draw_ctx: *SceneGraph,

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

    pub fn frustumCulling(self: *SceneGraph, scene_view_proj: zm.Mat) !void {
        self._opaque_sufaces_sorted.clearRetainingCapacity();
        try self._opaque_sufaces_sorted.ensureTotalCapacity(self.allocator, self.opaque_surfaces.items.len);

        for (self.opaque_surfaces.items, 0..) |*ro, i| {
            if (ro.isVisible(scene_view_proj)) {
                self._opaque_sufaces_sorted.appendAssumeCapacity(i);
            }
        }
    }
};
