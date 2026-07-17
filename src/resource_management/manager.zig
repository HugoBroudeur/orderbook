const std = @import("std");
const log = std.log.scoped(.asset_manager);
const zm = @import("zmath");
const Uuid = @import("uuid");
const Gltf = @import("zgltf").Gltf;
const Serde = @import("serde");

const ResourceManager = @This();
const Config = @import("../config.zig");

const Resource = @import("resource.zig").Resource;
const ResourceId = @import("resource.zig").ResourceId;
const RefCountedPool = @import("resource.zig").RefCountedPool;
const ResourceData = @import("resource.zig").ResourceData;
const ResourceHandle = @import("resource.zig").ResourceHandle;

const Engine = @import("../engine/vulkan/engine.zig");
const Objects = @import("../scene_management/objects.zig");
const LoadedGLTF = Objects.Model;
const Node = Objects.Node;
const Mesh = @import("mesh.zig").Mesh;
const Surface = @import("mesh.zig").Surface;
const Material = @import("material.zig").Material;
const Texture = @import("texture.zig").Texture;
const Image = @import("image.zig").Image;
const BasicTexture = @import("image.zig").BasicTexture;
const AllocatedImage = @import("../engine/vulkan/image.zig").AllocatedImage;

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
io: std.Io,
engine: *Engine,
pool: Pool,

// meshes: RefCountedPool(Mesh),
ref_pool: RefCountedPool,

const asset_dirs = [_][]const u8{
    "assets/meshes",
};

pub const ASSET_META_FILE_EXTENSION = ".dlmeta";

pub const AssetMetaFile = struct {
    guid: Uuid.Uuid,
    source_path: []const u8,
    name: []const u8,
};

pub const Pool = struct {
    pub const MAX_FILE_SIZE = 512_000_000_000;

    arena: std.heap.ArenaAllocator,

    asset_metadata: std.hash_map.AutoHashMap(Uuid.Uuid, AssetMetaFile),
    queued_gltf: std.hash_map.AutoHashMap(Uuid.Uuid, []const u8),
    queued_images: std.hash_map.AutoHashMap(Uuid.Uuid, []const u8),
    /// Loaded glTF models by asset GUID. The Model structs live in the arena;
    /// their resources (meshes/materials/textures) live in the ref pool.
    models: std.hash_map.AutoHashMap(Uuid.Uuid, *LoadedGLTF),

    fn init(allocator: std.mem.Allocator) Pool {
        return .{
            .queued_gltf = .init(allocator),
            .queued_images = .init(allocator),
            .asset_metadata = .init(allocator),
            .models = .init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    fn deinit(self: *Pool, allocator: std.mem.Allocator, engine: *Engine) void {
        _ = allocator;
        _ = engine;
        self.queued_gltf.deinit();
        self.asset_metadata.deinit();

        var it = self.models.valueIterator();
        while (it.next()) |model| model.*.deinit();
        self.models.deinit();
    }
};

pub fn init(allocator: std.mem.Allocator, io: std.Io, engine: *Engine) ResourceManager {
    const arena = std.heap.ArenaAllocator.init(allocator);

    var manager: ResourceManager = .{
        .allocator = allocator,
        .arena = arena,
        .engine = engine,
        .io = io,
        .pool = .init(allocator),
        .ref_pool = .init(allocator),
    };
    // Create common basic resources like 1px white image, etc...
    inline for (std.meta.tags(BasicTexture)) |kind| {
        _ = try manager.loadTexture(Texture.init(.{ .reserved = @intFromEnum(kind) }, @tagName(kind), .{ .basic = kind }));
    }

    return manager;
}

pub fn deinit(self: *ResourceManager, engine: *Engine) void {
    self.pool.deinit(self.allocator, engine);

    self.ref_pool.deinit(self);
}

// TODO, I need to improve that to make a copy of the file first, then save, then use the copy.
// That would prevent file corruption if stopped while saving
pub fn saveAssetPool(self: *ResourceManager, project_folder: []const u8) !void {
    // 1. Delete stale meta files: on-disk .dlmeta whose GUID isn't in asset_metadata anymore.
    const dir = try std.Io.Dir.cwd().openDir(self.io, project_folder, .{ .iterate = true });
    var it = dir.iterate();

    while (try it.next(self.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ASSET_META_FILE_EXTENSION)) continue;

        const path = try std.fs.path.join(self.allocator, &.{ project_folder, entry.name });
        defer self.allocator.free(path);

        if (self.loadMetaFile(path)) |meta| {
            if (!self.pool.asset_metadata.contains(meta.guid)) {
                try dir.deleteFile(self.io, entry.name);
                log.info("saveAssetPool: removed stale metafile {s}", .{entry.name});
            }
        }
    }

    var meta_it = self.pool.asset_metadata.iterator();
    while (meta_it.next()) |entry| {
        const meta = entry.value_ptr.*;
        const filename = std.fs.path.basename(meta.source_path);
        const metapath = try std.fmt.allocPrint(self.allocator, "{s}/{s}{s}", .{ project_folder, filename, ASSET_META_FILE_EXTENSION });
        defer self.allocator.free(metapath);

        self.saveMetaFile(metapath, meta) catch |err| {
            log.warn("saveAssetPool: failed to save metafile {s}: {}", .{ metapath, err });
        };
    }
}

pub fn loadAssetPool(self: *ResourceManager, project_folder: []const u8) !void {
    const dir = std.Io.Dir.cwd().openDir(self.io, project_folder, .{ .iterate = true }) catch return;
    var it = dir.iterate();
    while (try it.next(self.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ASSET_META_FILE_EXTENSION)) continue;
        const metapath = try std.fs.path.join(self.allocator, &.{ project_folder, entry.name });
        defer self.allocator.free(metapath);

        const meta = if (self.loadMetaFile(metapath)) |m| m else continue;

        std.Io.Dir.cwd().access(self.io, meta.source_path, .{ .read = true }) catch |err| {
            log.warn("loadAssetPool: error {} missing asset file for metafile {s}: {s}", .{ err, entry.name, meta.source_path });
            continue;
        };

        self.pool.queued_gltf.put(meta.guid, meta.source_path) catch |err| {
            log.warn("loadAssetPool: failed to queued asset {s}: {}", .{ meta.source_path, err });
            continue;
        };

        try self.pool.asset_metadata.put(meta.guid, meta);
        log.info("loadAssetPool: loaded {s} with GUID {}", .{ meta.source_path, meta.guid });
    }
}

fn saveMetaFile(self: *ResourceManager, metafile_path: []const u8, metafile: AssetMetaFile) !void {
    if (!std.mem.endsWith(u8, metafile_path, ASSET_META_FILE_EXTENSION)) {
        log.warn("saveMetaFile: invalid file extension '{s}'", .{metafile_path});
        return error.InvalidExtension;
    }

    const content = try Serde.zon.toSlice(self.allocator, metafile);
    defer self.allocator.free(content);

    try std.Io.Dir.writeFile(.cwd(), self.io, .{ .data = content, .sub_path = metafile_path, .flags = .{} });
    log.info("saveMetaFile: wrote metadata for GUID {}", .{metafile.guid});
}

fn loadMetaFile(self: *ResourceManager, metafile_path: []const u8) ?AssetMetaFile {
    if (!std.mem.endsWith(u8, metafile_path, ASSET_META_FILE_EXTENSION)) return null;

    const content = std.Io.Dir.cwd().readFileAlloc(self.io, metafile_path, self.allocator, .unlimited) catch |err| {
        log.warn("loadMetaFile: could not read {s}: {}", .{ metafile_path, err });
        return null;
    };
    defer self.allocator.free(content);

    return Serde.zon.fromSlice(AssetMetaFile, self.allocator, content) catch |err| {
        log.warn("loadMetaFile: failed to parse {s}: {}", .{ metafile_path, err });
        return null;
    };
}

pub fn importAsset(self: *ResourceManager, asset_path: []const u8) !Uuid.Uuid {
    if (self.findGuidForPath(asset_path)) |existing| {
        if (self.getAsset(existing) == null) {
            try self.loadGLTFAsset(self.engine, existing, asset_path);
        }
        return existing;
    }

    const guid = Uuid.v4.new(self.io);
    try self.loadGLTFAsset(self.engine, guid, asset_path);
    try self.pool.asset_metadata.put(guid, .{
        .guid = guid,
        .source_path = try self.allocator.dupe(u8, asset_path),
        .name = try self.allocator.dupe(u8, std.fs.path.stem(asset_path)),
    });
    return guid;
}

pub fn processQueuedAssets(self: *ResourceManager, engine: *Engine) void {
    var pending: std.ArrayList(struct { guid: Uuid.Uuid, path: []const u8 }) = .empty;
    defer pending.deinit(self.allocator);

    var it = self.pool.queued_gltf.iterator();
    while (it.next()) |entry| {
        pending.append(self.allocator, .{ .guid = entry.key_ptr.*, .path = entry.value_ptr.* }) catch continue;
    }

    for (pending.items) |item| {
        self.loadGLTFAsset(engine, item.guid, item.path) catch |err| {
            log.warn("processQueuedAssets: failed to load queued asset {s} (GUID {}): {}", .{ item.path, item.guid, err });
        };
    }
}

// pub fn processQueuedSkyboxes(self: *AssetManager, engine: *Engine) void {
//     if (self.pool.queued_images.count() == 0) return;
//     var pending: std.ArrayList(struct { guid: Uuid.Uuid, dir: []const u8 }) = .empty;
//     defer pending.deinit(self.allocator);
//
//     var it = self.pool.queued_images.iterator();
//
//     while (it.next()) |entry| {
//         pending.append(self.allocator, .{ .guid = entry.key_ptr.*, .dir = entry.value_ptr.* }) catch continue;
//     }
//     for (pending.items) |item| {
//         self.loadSkyboxCubemap(engine, item.guid, item.dir) catch |err| {
//             log.warn("processQueuedSkyboxes: failed to load {s} (GUID {}): {}", .{ item.dir, item.guid, err });
//         };
//         _ = self.pool.queued_images.remove(item.guid);
//         self.allocator.free(item.dir);
//     }
// }

fn findGuidForPath(self: *ResourceManager, path: []const u8) ?Uuid.Uuid {
    var it = self.pool.asset_metadata.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.source_path, path)) return entry.key_ptr.*;
    }
    return null;
}

// pub fn loadGltf(self: *AssetManager, engine: *Engine, asset_path: []const u8) !void {
//     const structure_file = try self.loadGLTFAsset(engine, asset_path);
//     const name = std.fs.path.stem(asset_path);
//     try self.pool.loaded_gltf.put(self.allocator, name, structure_file);
// }

pub fn getAsset(self: *ResourceManager, guid: Uuid.Uuid) ?*LoadedGLTF {
    return self.pool.models.get(guid);
}

pub fn loadMesh(self: *ResourceManager, mesh: Mesh) !ResourceHandle(Mesh) {
    return self.load(Mesh, mesh);
}

pub fn loadMaterial(self: *ResourceManager, material: Material) !ResourceHandle(Material) {
    return self.load(Material, material);
}

pub fn loadTexture(self: *ResourceManager, texture: Texture) !ResourceHandle(Texture) {
    return self.load(Texture, texture);
}

pub fn loadImage(self: *ResourceManager, image: Image) !ResourceHandle(Image) {
    return self.load(Image, image);
}

fn load(self: *ResourceManager, comptime T: type, value: T) !ResourceHandle(T) {
    if (self.ref_pool.incrementRef(T, value.getId())) {
        return .{ ._id = value.getId(), ._manager = self };
    }

    const ptr = try self.allocator.create(T);
    errdefer self.allocator.destroy(ptr);
    ptr.* = value;
    // name's backing memory belongs to the caller (often glTF-owned data,
    // freed once loadGLTFAsset's `gltf.deinit()` runs) and may not survive
    // past this call — dupe it so the pooled resource owns a stable copy.
    // id needs no such dupe: it's a plain ResourceId value now, not a
    // pointer into memory someone else owns.
    ptr.name = try self.allocator.dupe(u8, value.name);
    errdefer self.allocator.free(ptr.name);

    try ptr.load(self);
    try self.ref_pool.put(T, ptr.interface());

    return .{ ._id = ptr.getId(), ._manager = self };
}

pub fn getResource(self: *ResourceManager, comptime T: type, id: ResourceId) ?*T {
    return self.ref_pool.get(T, id);
}

pub fn release(self: *ResourceManager, comptime T: type, id: ResourceId) void {
    self.ref_pool.remove(T, id, self);
}

// pub fn getCubeImage(self: *AssetManager, guid: Uuid.Uuid) ?*Image {
//     return (self.pool._cubemaps.get(guid) orelse return null).image;
// }
pub fn queueSkybox(self: *ResourceManager, guid: Uuid.Uuid, dir_path: []const u8) !void {
    if (self.pool._cubemaps.contains(guid) or self.pool.queued_images.contains(guid)) return;
    const owned = try self.allocator.dupe(u8, dir_path);

    // const faces = .{
    //     .px = try std.fs.path.join(self.allocator, &.{ dir_path, "px.png" }),
    //     .nx = try std.fs.path.join(self.allocator, &.{ dir_path, "nx.png" }),
    //     .py = try std.fs.path.join(self.allocator, &.{ dir_path, "py.png" }),
    //     .ny = try std.fs.path.join(self.allocator, &.{ dir_path, "ny.png" }),
    //     .pz = try std.fs.path.join(self.allocator, &.{ dir_path, "pz.png" }),
    //     .nz = try std.fs.path.join(self.allocator, &.{ dir_path, "nz.png" }),
    // };
    // defer inline for (.{ faces.px, faces.nx, faces.py, faces.ny, faces.pz, faces.nz }) |p| self.allocator.free(p);

    const image = try self.pool.arena.allocator().create(AllocatedImage);
    image.* = AllocatedImage.init(.{ .cubemap_path = dir_path }, true);
    // image.* = try Image.createCubemapFromPath(engine, faces, .r8g8b8a8_srgb, .{ .sampled_bit = true }, true);

    try self.pool.queued_images.put(self.allocator, guid, owned);
}

// fn loadSkyboxCubemap(self: *AssetManager, guid: Uuid.Uuid, dir_path: []const u8) !void {
//     try self.pool._cubemaps.put(self.allocator, guid, .{ .image = image, .bindless_slot = slot });
// }

/// Identifies what a `ResourceId` is derived from — the one call surface
/// every loader uses (`makeId`) instead of remembering which of several
/// id-building functions applies to which resource kind.
pub const IdSource = union(enum) {
    /// A resource whose identity is scoped to one file: its position in
    /// that file's own array. Used for glTF-internal meshes/materials/
    /// textures/embedded images.
    local: struct { file_guid: Uuid.Uuid, index: u32 },
    /// A resource whose identity must match across files by content —
    /// currently only file-backed Image dedup by URI.
    content: []const u8,
    /// Fixed identity for engine-intrinsic resources that have no source
    /// file at all — currently only the basic placeholder textures (see
    /// `BasicTexture`). Safe from colliding with `.local`/`.content`: both
    /// of those are ~uniform over the full 128-bit space, `.reserved` only
    /// ever takes the small hand-assigned values below.
    reserved: u32,
};

pub fn makeId(source: IdSource) ResourceId {
    return switch (source) {
        .local => |l| l.file_guid ^ @as(u128, l.index),
        .content => |bytes| blk: {
            const lo: u64 = std.hash.Wyhash.hash(0x5A5A_5A5A, bytes);
            const hi: u64 = std.hash.Wyhash.hash(0xA5A5_A5A5, bytes);
            break :blk (@as(u128, hi) << 64) | @as(u128, lo);
        },
        .reserved => |r| r,
    };
}

// TODO, decouple engine such as the asset is loaded in the pool then have a function to load the pool in the GPU
pub fn loadGLTFAsset(self: *ResourceManager, engine: *Engine, guid: Uuid.Uuid, file_path: []const u8) !void {
    var gltf = Gltf.init(self.allocator);
    defer gltf.deinit();

    const extension = std.fs.path.extension(file_path);
    const filename = std.fs.path.stem(file_path);

    if (std.mem.eql(u8, extension, ".glb") or std.mem.eql(u8, extension, ".gltf")) {
        const cwd = std.Io.Dir.cwd();
        const buffer = try cwd.readFileAllocOptions(self.io, file_path, self.allocator, std.Io.Limit.limited(ResourceManager.MAX_FILE_SIZE), .@"4", null);
        try gltf.parse(buffer);
    } else {
        return error.FileNotSupported;
    }

    if (null == gltf.glb_binary) return error.GlbBinaryEmpty;
    // const glb_binary = gltf.glb_binary.?;

    var model: *LoadedGLTF = try self.pool.arena.allocator().create(LoadedGLTF);
    model.* = try LoadedGLTF.init(self.allocator);
    model.creator = engine;

    const initial_node_index = 0;

    var nodes: std.ArrayList(*Node) = try .initCapacity(self.allocator, gltf.data.nodes.len);
    defer nodes.deinit(self.allocator);

    const bindless_slots = try self.allocator.alloc(u32, gltf.data.textures.len);
    defer self.allocator.free(bindless_slots);

    if (Config.log.mesh) {
        log.info("[DBG] GLTF images: {d}, materials: {d}, textures: {d}", .{ gltf.data.images.len, gltf.data.materials.len, gltf.data.textures.len });
    }

    // Load Textures — each Texture resource resolves its sampler from the
    // engine cache and ref-count-loads its Image dependency, so an image
    // shared by several textures uploads once. Must complete before any
    // material loads: material records store final bindless slot ids.
    for (gltf.data.textures, 0..) |_, i| {
        // glTF textures carry no name field, unlike meshes/materials —
        // positional fallback is the only option, same shape as the
        // mesh/material fallbacks below.
        const name = std.fmt.allocPrint(self.allocator, "texture_idx_{d}", .{i}) catch "";
        const tex_id = makeId(.{ .local = .{ .file_guid = guid, .index = @intCast(i) } });
        const handle = try self.loadTexture(Texture.init(tex_id, name, .{
            .gltf_texture = .{ .gltf = &gltf, .texture_idx = @intCast(i), .guid = guid },
        }));
        bindless_slots[i] = handle.get().?.slot;
        try model.textures.put(self.allocator, name, handle.get().?);

        if (Config.log.mesh) {
            log.info("[DBG] textures[{d}] → bindless slot {d}", .{ i, bindless_slots[i] });
        }
    }

    // Load Materials — grow the shared material buffer at most once per glTF
    // (registerMaterial would otherwise resize up to once per material).
    try engine.descriptor.ensureMaterialCapacity(@intCast(gltf.data.materials.len));

    var local_materials: std.ArrayList(*Material) = try .initCapacity(self.allocator, gltf.data.materials.len);
    defer local_materials.deinit(self.allocator);

    for (gltf.data.materials, 0..) |gltf_material, material_idx| {
        const name = gltf_material.name orelse std.fmt.allocPrint(self.allocator, "material_idx_{}", .{material_idx}) catch "";
        // Id is scoped to this file's guid + this material's array position
        // (makeId(.local)) — glTF material names (explicit or the
        // positional fallback above) are only unique within one file, and
        // two files sharing a name (generic exporter defaults like
        // "Material.001" collide constantly) would otherwise dedup onto the
        // wrong file's already-loaded material if the id were name-based.
        const id = makeId(.{ .local = .{ .file_guid = guid, .index = @intCast(material_idx) } });

        const handle = try self.loadMaterial(Material.init(id, name, .{
            .gltf_material = .{ .gltf = &gltf, .material_idx = @intCast(material_idx), .bindless_slots = bindless_slots },
        }));
        local_materials.appendAssumeCapacity(handle.get().?);
        try model.materials.put(self.allocator, name, handle.get().?);
    }

    // Load Meshes
    for (gltf.data.meshes, 0..) |mesh, mesh_idx| {
        const name = mesh.name orelse std.fmt.allocPrint(self.allocator, "mesh_idx_{}", .{mesh_idx}) catch "";
        // Same reasoning as materials above — generic exporter names
        // ("Plane.001" etc.) collide across files constantly, which used to
        // silently reuse another file's already-loaded geometry AND rebind
        // its surfaces to this file's materials on dedup.
        const id = makeId(.{ .local = .{ .file_guid = guid, .index = @intCast(mesh_idx) } });

        const handle = try self.loadMesh(Mesh.init(id, name, .{
            .gltf_item = .{ .gltf = &gltf, .mesh_idx = @intCast(mesh_idx) },
        }));
        handle.get().?.bindMaterials(local_materials.items);

        try model.meshes.put(self.allocator, name, handle.get().?);
    }

    // Load Nodes
    for (gltf.data.nodes, 0..) |gltf_node, i| {
        const name = gltf_node.name orelse blk: {
            const alt_name = std.fmt.allocPrint(self.allocator, "unamed_idx_{}", .{i}) catch "";

            break :blk alt_name;
        };
        var local_transform: zm.Mat = zm.identity();

        if (gltf_node.matrix) |matrix| {
            inline for (0..4) |row| {
                inline for (0..4) |col| {
                    local_transform[row][col] = matrix[row * 4 + col];
                }
            }
        } else {
            const transform: zm.Vec = .{ gltf_node.translation[0], gltf_node.translation[1], gltf_node.translation[2], 1 };
            const rotation: zm.Quat = .{ gltf_node.rotation[0], gltf_node.rotation[1], gltf_node.rotation[2], gltf_node.rotation[3] };
            const scale: zm.Vec = blk: {
                const s = gltf_node.scale;
                if (s[0] == 0 and s[1] == 0 and s[2] == 0) break :blk .{ 1, 1, 1, 0 };
                break :blk .{ s[0], s[1], s[2], 0 };
            };

            const tm = zm.translationV(transform);
            const rm = zm.quatToMat(rotation);
            const sm = zm.scalingV(scale);
            const sr = zm.mul(sm, rm);
            local_transform = zm.mul(sr, tm);
        }

        const node = try self.pool.arena.allocator().create(Node);

        if (gltf_node.mesh) |mesh_idx| {
            const mesh_name = gltf.data.meshes[mesh_idx].name orelse std.fmt.allocPrint(self.allocator, "mesh_idx_{}", .{mesh_idx}) catch "";
            node.* = Node.init(self.allocator, .{ .mesh = model.meshes.get(mesh_name).? });
        } else {
            node.* = Node.init(self.allocator, .basic);
        }
        node.local_transform = local_transform;
        nodes.appendAssumeCapacity(node);

        try model.nodes.put(self.allocator, name, nodes.items[initial_node_index + i]);
    }

    // Create Node hierarchy
    for (gltf.data.nodes, 0..) |node, i| {
        const scene_node = nodes.items[initial_node_index + i];

        for (node.children) |j| {
            const child_ptr = nodes.items[initial_node_index + j];
            try scene_node.child_nodes.append(self.allocator, child_ptr);
            child_ptr.parent_node = scene_node;
        }
    }

    // Find the top Nodes with no parents
    for (nodes.items[initial_node_index..]) |node| {
        if (node.parent_node == null) {
            try model.top_nodes.append(self.allocator, node);
            node.refreshTransform(zm.identity());
        }
    }

    try self.pool.models.put(guid, model);

    if (!self.pool.queued_gltf.remove(guid)) {
        log.warn("GLTF loaded without being in the queue. The application code is wrong. GUID: {} | name: {s}", .{ guid, filename });
    }
}

pub fn resolveMeshPath(self: *ResourceManager, name: []const u8) !?[]const u8 {
    for (asset_dirs) |dir_path| {
        const dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch continue;
        var it = dir.iterate();
        while (try it.next(self.io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.eql(u8, std.fs.path.stem(entry.name), name)) continue;
            return try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
        }
    }
    return null;
}
