const std = @import("std");
const AssetManager = @import("manager.zig");

pub const Mesh = @import("mesh.zig").Mesh;
pub const Material = @import("material.zig").Material;
pub const Texture = @import("texture.zig").Texture;
pub const Image = @import("image.zig").Image;

/// Type-erased resource handle. This is the work-item currency for the
/// (future) async loading queue: a heterogeneous list of pending loads can
/// hold plain `Resource` values and call `.load()` without knowing the
/// concrete type.
///
/// The vtable is intentionally minimal (getId/load/unload). There is no
/// setDataSource: callers construct resources fully (`T.init(id, source)`
/// with each type's own typed `Source` union) before handing them to the
/// AssetManager, so sources never squeeze through the erased interface.
pub const Resource = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        getId: *const fn (*const anyopaque) []const u8,
        load: *const fn (*anyopaque, *AssetManager) anyerror!void,
        unload: *const fn (*anyopaque, *AssetManager) void,
    };

    pub fn getId(self: *const Resource) []const u8 {
        return self.vtable.getId(self.ptr);
    }

    pub fn load(self: *Resource, mgr: *AssetManager) !void {
        try self.vtable.load(self.ptr, mgr);
    }

    pub fn unload(self: *Resource, mgr: *AssetManager) void {
        self.vtable.unload(self.ptr, mgr);
    }

    pub fn interface(ptr: anytype) Resource {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn getId(impl: *const anyopaque) []const u8 {
                const self: T = @ptrCast(@alignCast(@constCast(impl)));
                return ptr_info.pointer.child.getId(self);
            }
            fn load(impl: *anyopaque, mgr: *AssetManager) anyerror!void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.load(self, mgr);
            }
            fn unload(impl: *anyopaque, mgr: *AssetManager) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.unload(self, mgr);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .getId = Impl.getId,
                .load = Impl.load,
                .unload = Impl.unload,
            },
        };
    }
};

pub fn ResourceHandle(comptime T: type) type {
    return struct {
        const Self = @This();
        _id: []const u8,
        _manager: *AssetManager,

        pub fn get(self: Self) ?*T {
            return self._manager.getResource(T, self._id);
        }
    };
}

pub const ResourceData = struct {
    value: *Resource,
    ref_count: u32 = 1,
};

/// Two maps on purpose: `ref_counts` is the handle table (an id can be
/// requested and ref-counted synchronously), `pool` the residency table
/// (the payload appears when loading completes). The split keeps
/// "requested but not yet resident" representable once loading goes async.
pub const RefCountedPool = struct {
    allocator: std.mem.Allocator,
    /// @typeName(T) -> id -> Resource
    pool: std.StringHashMap(std.StringHashMap(Resource)),
    /// @typeName(T) -> id -> ResourceData
    ref_counts: std.StringHashMap(std.StringHashMap(ResourceData)),

    pub fn init(allocator: std.mem.Allocator) RefCountedPool {
        return .{ .allocator = allocator, .pool = .init(allocator), .ref_counts = .init(allocator) };
    }

    pub fn deinit(self: *RefCountedPool, mgr: *AssetManager) void {
        // Only the pool contains the actual resources data
        var it = self.pool.valueIterator();
        while (it.next()) |id_map| {
            var id_it = id_map.valueIterator();
            while (id_it.next()) |entry| entry.*.unload(mgr);
            id_map.deinit();
        }
        self.pool.deinit();

        var rc_it = self.ref_counts.valueIterator();
        while (rc_it.next()) |id_map| id_map.deinit();
        self.ref_counts.deinit();
    }

    pub fn count(self: *RefCountedPool) u32 {
        return self.pool.count();
    }

    fn typedPool(self: *RefCountedPool, comptime T: type) !*std.StringHashMap(Resource) {
        const pool = try self.pool.getOrPut(@typeName(T));
        if (!pool.found_existing) pool.value_ptr.* = .init(self.allocator);
        return pool.value_ptr;
    }

    fn typedRefCount(self: *RefCountedPool, comptime T: type) !*std.StringHashMap(ResourceData) {
        const ref_count = try self.ref_counts.getOrPut(@typeName(T));
        if (!ref_count.found_existing) ref_count.value_ptr.* = .init(self.allocator);
        return ref_count.value_ptr;
    }

    pub fn incrementRef(self: *RefCountedPool, comptime T: type, id: []const u8) bool {
        const ref_count = self.typedRefCount(T) catch return false;
        const entry = ref_count.getPtr(id) orelse return false;
        entry.ref_count += 1;
        return true;
    }

    // Add a new resource to the pool
    pub fn put(self: *RefCountedPool, comptime T: type, resource: Resource) !void {
        if (!self.incrementRef(T, resource.getId())) {
            try (try self.typedPool(T)).put(resource.getId(), resource);
            const res = (try self.typedPool(T)).getPtr(resource.getId()).?;
            try (try self.typedRefCount(T)).put(resource.getId(), .{ .value = res, .ref_count = 1 });
        }
    }

    pub fn get(self: *RefCountedPool, comptime T: type, id: []const u8) ?*T {
        const pool = self.typedPool(T) catch return null;
        if (pool.get(id)) |res| {
            return @ptrCast(@alignCast(res.ptr));
        }

        return null;
    }

    pub fn remove(self: *RefCountedPool, comptime T: type, id: []const u8, mgr: *AssetManager) void {
        const ref_count = self.typedRefCount(T) catch return;
        const entry = ref_count.getPtr(id) orelse return;

        if (entry.ref_count > 0) entry.ref_count -= 1;

        if (entry.ref_count == 0) {
            const pool = self.typedPool(T) catch return;
            var resource = pool.get(id) orelse return;
            resource.unload(mgr);

            _ = ref_count.remove(id);
            _ = pool.remove(id);

            // The pooled resource owns its id (duped by AssetManager.loadAny)
            // and its own struct allocation.
            const typed: *T = @ptrCast(@alignCast(resource.ptr));
            self.allocator.free(typed.id);
            self.allocator.destroy(typed);
        }
    }
};
