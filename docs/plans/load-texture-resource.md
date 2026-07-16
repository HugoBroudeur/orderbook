# Texture loading: Image resource + Texture resource, dedup by composition

## Decisions this plan is built on

1. **The vtable `Resource` interface stays** — its type erasure is the
   work-item currency for the planned async loading queue (heterogeneous
   pending loads as plain `Resource` values, workers call `.load()` without
   knowing concrete types).
2. **The two-map `RefCountedPool` stays** — `ref_counts` is the *handle
   table* (request/ref synchronously, immediately), `pool` the *residency
   table* (payload appears when loading completes). The split is what makes
   "requested but not yet resident" representable for async.
3. **`load`/`unload` receive the `AssetManager`** (engine via `mgr.engine`)
   so resources compose: `Texture.load` ref-count-loads its `Image`
   dependency and releases it in `unload`.
4. **`setDataSource` leaves the interface; the caller constructs the
   resource.** The manager's job starts at a fully-constructed, *inert*
   value: `Mesh.init(id, source)` stores id + source and does nothing else.
   Public API becomes typed per-resource entry points —
   `loadMesh(mesh: Mesh)`, `loadTexture(texture: Texture)`, ... — each a
   one-liner over a single private generic that owns the pool plumbing.

### Prior art for per-type load entry points (point 4)

- **raylib** — the whole asset API is typed load functions:
  [`LoadTexture`, `LoadModel`, `LoadFont`, `LoadFontEx`, ...](https://www.raylib.com/cheatsheet/raylib_cheatsheet_v4.0.pdf),
  each dispatching internally to format-specific loaders
  ([rtextures.c](https://github.com/raysan5/raylib/blob/master/src/rtextures.c)).
- **OGRE** — one manager per resource type
  ([`TextureManager`](https://ogrecave.github.io/ogre/api/1.11/class_ogre_1_1_texture_manager.html),
  `MeshManager`, `MaterialManager`, `FontManager`, `SkeletonManager`), each
  with typed `load`/`create` returning a ref-counted `TexturePtr`/`MeshPtr`.
  Directly relevant to the async goal: OGRE folds get-or-create into one
  call *specifically* so two threads can't race a `getByName` miss into a
  double `create` — the same reason `loadAny` below checks the ref table
  and inserts in one place.
- **Doom 3 BFG** —
  [`idImageManager::ImageFromFile(name, filter, repeat, usage)`](https://github.com/id-Software/DOOM-3-BFG/blob/master/neo/renderer/Image.h):
  typed entry point, dedup keyed on name+params, returns the existing
  `idImage*` on a repeat request. (Its docs warn that the same file with
  different filter params loads a second copy — the exact duplication your
  Image/Texture split avoids, since sampler params live on `Texture`, not
  on the deduped `Image`.)

### Interface after the change

```zig
// resource.zig — vtable shrinks to three entries, load/unload gain the manager
const VTable = struct {
    getId: *const fn (*const anyopaque) []const u8,
    load: *const fn (*anyopaque, *AssetManager) anyerror!void,
    unload: *const fn (*anyopaque, *AssetManager) void,
};
```

Dropping `setDataSource` has a payoff beyond a smaller vtable: sources no
longer squeeze through the erased interface, so **each type declares its
own typed `Source` union** (the good idea from
[resource-source-union.md](resource-source-union.md), now compatible with
keeping the interface). The shared `Resource.DataSource` union is deleted —
no more accumulating `gltf_image`/`gltf_texture`/... variants that only one
type each understands, and passing a mesh-shaped source to a Texture
becomes a compile error instead of a runtime panic.

`Mesh` and `Material` port to the same shape:
`Mesh.Source = union(enum) { gltf_item: struct { gltf: *Gltf, mesh_idx: u32 } }`;
`Material.Source` carries `bindless_slots` as a typed field — same
mechanism the material plan already uses, minus the shared-union
threading.

### `AssetManager` — typed entry points over one generic

```zig
pub fn loadMesh(self: *AssetManager, mesh: Mesh) !ResourceHandle(Mesh) {
    return self.loadAny(Mesh, mesh);
}
pub fn loadMaterial(self: *AssetManager, material: Material) !ResourceHandle(Material) {
    return self.loadAny(Material, material);
}
pub fn loadTexture(self: *AssetManager, texture: Texture) !ResourceHandle(Texture) {
    return self.loadAny(Texture, texture);
}
pub fn loadImage(self: *AssetManager, image: Image) !ResourceHandle(Image) {
    return self.loadAny(Image, image);
}

/// The only place that touches pool plumbing. `value` must be inert
/// (constructed by T.init — id + source only, no allocations, no GPU work),
/// so discarding it on a dedup hit is free.
fn loadAny(self: *AssetManager, comptime T: type, value: T) !ResourceHandle(T) {
    if (self.ref_pool.incrementRef(T, value.getId())) {
        // Return the RESIDENT copy's id (stable for the resource's
        // lifetime) — not value.getId(), whose backing memory belongs
        // to the caller and may be freed after this call.
        const resident = self.ref_pool.get(T, value.getId()).?;
        return .{ ._id = resident.getId(), ._manager = self };
    }

    const ptr = try self.allocator.create(T);
    errdefer self.allocator.destroy(ptr);
    ptr.* = value;
    try ptr.load(self);
    try self.ref_pool.put(T, ptr.interface());

    return .{ ._id = ptr.getId(), ._manager = self };
}
```

Id ownership convention: the pool keys and handles reference the resident
resource's `id`, so `T.init` should receive an id the resource will own
until `unload` (dupe at the call site, free in `unload`). On a dedup hit
the caller frees its own temporary id (`defer`).

One entry point per type is one line each — and it gives each type room to
diverge later (e.g. `loadTexture` growing a sampler-override parameter)
without touching the generic plumbing, which is written exactly once.

## The dedup design

The requirement: an image used by two textures — even with different
samplers — must upload to the GPU **once**. The split that makes this fall
out of ref-counting instead of special-case logic:

- **`Image`** — the content. Identity = pixel source (URI, or file-local
  embedded index). Knows nothing about samplers. Heavy: decode + staging +
  upload.
- **`Texture`** — the pairing (image, sampler) → bindless slot. Cheap: its
  own GPU cost is one descriptor-array entry. Holds a ref-counted `*Image`.
- **Sampler** — not a resource. Flyweight cache on `Engine`:
  `getSampler(option: SamplerOption) !Sampler`, linear scan +
  `std.meta.eql` (a project uses under a dozen unique combos ever; float
  fields make hashing awkward). `Engine.deinit` destroys cache entries —
  nobody else ever does.

Two textures → same image, different samplers: both compute the same
`image_id`, the second `loadImage` is a pool hit (`ref_count = 2`, zero
GPU work), each registers its own bindless slot pairing the shared image
view with its own sampler. One upload. The ref pool *is* the dedup
mechanism.

### `image.zig` (new)

```zig
pub const Image = struct {
    id: []const u8,
    source: Source,
    allocated_image: AllocatedImage = undefined,
    /// False when load fell back to error_checker (image owned by engine).
    owns_image: bool = true,

    pub const Source = union(enum) {
        gltf_image: struct { gltf: *Gltf, image_idx: u32 },
        file: []const u8,
        /// glTF texture had no source image → error_checker fallback.
        missing,
    };

    pub fn interface(self: *Image) Resource { return Resource.interface(self); }
    pub fn init(id: []const u8, source: Source) Image {
        return .{ .id = id, .source = source };
    }
    pub fn getId(self: *const Image) []const u8 { return self.id; }

    pub fn load(self: *Image, mgr: *AssetManager) !void {
        const engine = mgr.engine;
        const kind: ?ImageDataKind = switch (self.source) {
            .gltf_image => |s| blk: {
                const img = s.gltf.data.images[s.image_idx];
                break :blk if (img.uri) |uri|
                    .{ .path = uri }
                else if (img.data) |d|
                    .{ .pixels = .{ .data = d } }
                else
                    null;
            },
            .file => |path| .{ .path = path },
            .missing => null,
        };

        if (kind) |k| {
            const meta = ImageMetadata.init(k, null);
            self.allocated_image = try meta.allocateImage(engine, .{ .sampled_bit = true }, true, 1);
            try meta.upload(engine, self.allocated_image);
        } else {
            self.allocated_image = engine.images.get(.error_checker);
            self.owns_image = false;
        }
    }

    pub fn unload(self: *Image, mgr: *AssetManager) void {
        if (self.owns_image) self.allocated_image.destroy(mgr.engine);
        mgr.allocator.free(self.id);
    }
};
```

(`owns_image` replaces the error_checker vk-handle comparison currently in
`ResourceManager.deinit`, `manager.zig:111-118` — ownership decided where
the fallback happens, not re-derived at teardown.)

### `texture.zig` (rewritten)

```zig
pub const Texture = struct {
    id: []const u8,
    source: Source,
    image: *Image = undefined,
    /// Kept to release the Image ref in unload. Owned by this Texture.
    image_id: []const u8 = "",
    /// Copied from the engine sampler cache — never destroyed here.
    sampler: Sampler = undefined,
    /// Bindless slot in the global 2D texture array (binding 3).
    slot: u32 = 0,

    pub const Source = union(enum) {
        gltf_texture: struct { gltf: *Gltf, texture_idx: u32, guid: Uuid.Uuid },
    };

    pub fn interface(self: *Texture) Resource { return Resource.interface(self); }
    pub fn init(id: []const u8, source: Source) Texture {
        return .{ .id = id, .source = source };
    }
    pub fn getId(self: *const Texture) []const u8 { return self.id; }

    pub fn load(self: *Texture, mgr: *AssetManager) !void {
        const engine = mgr.engine;
        const s = self.source.gltf_texture;
        const gltf_texture = s.gltf.data.textures[s.texture_idx];

        // Sampler: glTF record → SamplerOption → engine cache (or default).
        self.sampler = if (gltf_texture.sampler) |sampler_idx|
            try engine.getSampler(samplerOptionFromGltf(s.gltf.data.samplers[sampler_idx]))
        else
            engine.samplers.get(.linear);

        // Image: ref-counted composition. Identity is sampler-independent,
        // so N textures sharing pixels → one upload, ref_count = N.
        if (gltf_texture.source) |image_idx| {
            self.image_id = try imageId(mgr.allocator, s.gltf, @intCast(image_idx), s.guid);
            const handle = try mgr.loadImage(Image.init(self.image_id, .{
                .gltf_image = .{ .gltf = s.gltf, .image_idx = @intCast(image_idx) },
            }));
            self.image = handle.get().?;
        } else {
            self.image_id = try std.fmt.allocPrint(mgr.allocator, "{f}#missing", .{s.guid});
            const handle = try mgr.loadImage(Image.init(self.image_id, .missing));
            self.image = handle.get().?;
        }

        // The texture's own GPU footprint: one (image view, sampler) pair
        // registered on the bindless array.
        self.slot = try engine.descriptor.registerTexture(&self.image.allocated_image, &self.sampler);
    }

    pub fn unload(self: *Texture, mgr: *AssetManager) void {
        mgr.release(Image, self.image_id);
        mgr.allocator.free(self.image_id);
        mgr.allocator.free(self.id);
        // sampler: cache-owned. slot: append-only registry, not reclaimed
        // (same accepted limitation as material slots).
    }

    /// URI when the image is file-backed (dedupes across glTF files that
    /// reference the same texture file); guid#img{idx} for embedded images
    /// (file-local — no cross-file identity exists to exploit).
    fn imageId(allocator: std.mem.Allocator, gltf: *Gltf, image_idx: u32, guid: Uuid.Uuid) ![]const u8 {
        const img = gltf.data.images[image_idx];
        return if (img.uri) |uri|
            try allocator.dupe(u8, uri)
        else
            try std.fmt.allocPrint(allocator, "{f}#img{d}", .{ guid, image_idx });
    }
};
```

`samplerOptionFromGltf` = today's `extractFilter`/`extractMipmapMode` +
wrap-mode switches (`manager.zig:411-431, 876-888`), moved into
`texture.zig`.

Note on `image_id` and dedup: when the second texture's `loadImage` hits
the pool, the resident Image keeps its own id copy and the incoming one is
still owned by the Texture (freed in its `unload`) — two allocations of the
same string, one owner each, no double-free.

Note `handle.get().?` immediately after `mgr.loadImage` assumes dependency
loads complete synchronously — true today. When loading goes async,
dependency resolution inside `load()` is the one place that must stay
synchronous (or grow await semantics); flagging it now so the async design
accounts for it.

`AssetManager.release` needs a comptime-typed form to match
(`release(self, comptime T, id)` → `self.ref_pool.remove(T, id)`) — the
current `release` (`manager.zig:336-340`) references `pool.meshes`, which
no longer exists.

### `manager.zig` — the three loops become one

Texture ids can be file-local (`{guid}#tex{i}`) — cross-file dedup happens
at the Image level, where the actual cost lives:

```zig
for (gltf.data.textures, 0..) |_, i| {
    const tex_id = try std.fmt.allocPrint(self.allocator, "{f}#tex{d}", .{ guid, i });
    const handle = try self.loadTexture(Texture.init(tex_id, .{
        .gltf_texture = .{ .gltf = &gltf, .texture_idx = @intCast(i), .guid = guid },
    }));
    bindless_slots[i] = handle.get().?.slot;
    try model.textures.put(self.allocator, tex_id, handle.get().?);
}
```

The sampler loop (`:410-435`), image loop (`:459-513`) and texture loop
(`:522-535`) all collapse into this. `bindless_slots` stays, so the
[load-material-resource plan](load-material-resource.md) is untouched —
though when that plan lands, `Material.Source` carries `bindless_slots` as
a typed field instead of a shared-`DataSource` payload.

## What the async bet needs later (not this plan, but don't preclude it)

- **State on `ResourceData`** (`queued / loading / ready / failed`) so
  `ref_counts` can hold handles for not-yet-resident resources and
  `ResourceHandle.get()` can honestly return `null` while in flight.
- **Per-map locking** — `ref_counts` mutex (hot, main-thread
  acquire/release) separate from `pool` mutex (worker-completion inserts);
  never hold either while calling a resource's `load()`. `loadAny` being
  the single get-or-create point is what makes this lockable at all
  (OGRE's stated rationale for the same shape).
- **Phase the GPU work**: workers do file I/O + decode; GPU upload stays on
  the main thread via a completion queue first (today's `Buffer.transfer`
  does `queueWaitIdle` on the graphics queue — not thread-safe). A
  dedicated transfer queue is phase 2.

## Follow-up unlocked (not this plan): materials compose textures too

Once `load(mgr)` composition exists, `Material.load` can resolve its own
texture dependencies (`mgr.loadTexture(...)` → read `.slot`) instead of
receiving a pre-built `bindless_slots` array through its `Source`. That
deletes the array threading entirely and makes ref-counting model the true
dependency graph: Model → Materials → Textures → Images. Do it after this
plan and load-material-resource.md have both landed.

## Step-by-step

1. `resource.zig`: vtable shrinks to `getId`/`load`/`unload` (drop
   `setDataSource`, add `*AssetManager` to load/unload); rewire `Impl`
   wrappers; `RefCountedPool._engine` → `_manager`; delete the shared
   `DataSource` union.
2. Port `Mesh`/`Material`: each gains its own `Source` union +
   `init(id, source)`; `load` bodies use `mgr.engine` (mechanical).
3. `manager.zig`: replace `load(T, id, source)` with `loadAny` + the typed
   `loadMesh`/`loadMaterial`/`loadTexture`/`loadImage` entry points; fix
   `release` to the comptime-typed form.
4. `engine.zig`: `sampler_cache` + `getSampler`; destroy cache entries in
   `deinit`.
5. New `resource_management/image.zig`; rewrite
   `resource_management/texture.zig`; move `samplerOptionFromGltf` in;
   export both from `resource.zig`.
6. `manager.zig` `loadGLTFAsset`: replace the three loops with the texture
   loop; delete `pool._images`, `_current_img_idx`, the error_checker
   special-case in `ResourceManager.deinit`, and the dead
   `alpha_matter_image_idx` block.
7. `objects.zig`: `Model.images`/`samplers` → `textures:
   std.array_hash_map.String(*Resource.Texture)`; `deinit` stops
   destroying samplers.
8. Verify: load a glTF where two textures share one image with different
   samplers — confirm exactly **one** image upload (log in `Image.load`),
   two bindless slots, `ref_count = 2` on the image; unload the model and
   confirm the image frees only after both textures release.

## Out of scope

- **Slot reclamation** — bindless registry stays append-only; unloads leak
  slots. Same limitation as material slots; fix together when eviction
  becomes real.
- **Cubemaps/skybox** — `registerCubemap` path untouched.
- **The async loader itself** — requirements sketched above so this plan
  doesn't paint over them; design it separately.
