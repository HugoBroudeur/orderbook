# Single shared, growable material buffer in the Resource Manager

## Context

`AssetManager` already declares the intent in a comment (`src/resource_management/manager.zig:42-44`):

```zig
/// The choice made is to have 1 buffer for all material data
/// it needs to be managed when a new Material is loaded
pbr_material_buffer: Buffer,
```

but `init` never sets it (this is the `missing struct field: pbr_material_buffer`
build error), and `loadGLTFAsset` doesn't use it at all. Instead, every call to
`loadGLTFAsset` (`manager.zig:519-524`) does:

```zig
var buffer = try PBRMaterial.createMaterialPushConstantsBuffer(engine, @intCast(gltf.data.materials.len));
loaded_gltf.material_data_buffer = buffer;
loaded_gltf.material_data_buffer_slot_idx = try engine.registerBuffer(&buffer, 0);
```

i.e. **one storage buffer + one bindless slot per glTF**, sized exactly to
that file's material count, owned and destroyed by `Objects.Model`
(`scene_management/objects.zig:154,184`). Each `Material`'s `material_idx`
(`manager.zig:627`) is a local index into that file's own buffer.

This works but doesn't scale to a shared pool: every asset burns a bindless
buffer slot regardless of how few materials it has, and there's no path for
appending materials to an existing buffer. The ask is to consolidate to
**one buffer for all materials, ever loaded**, growing it in place when it
runs out of room — using the `Buffer.resize` we just implemented
(`src/engine/vulkan/buffer.zig:203`, create-new/copy/destroy-old).

### Depends on: [bindless-descriptor-manager](bindless-descriptor-manager.md)

That plan moves `registerTexture`/`registerBuffer`/`registerCubemap` and the
bindless caches off `Engine` and into `Engine.descriptor` (a `BindlessRegistry`,
`src/engine/vulkan/bindless.zig`), and adds `updateBufferSlot` there rather
than on `Engine` directly. This plan is written against that end state:
`AssetManager` — the resource-management layer — talks to the bindless
registry purely through `engine.descriptor.registerBuffer(...)` /
`engine.descriptor.updateBufferSlot(...)`, and never touches `buffer_cache`
or any other registry internals directly. That's the Service Locator pattern
the README's [architecture reference](../../README.md#architecture) calls
for: `Engine` is the locator, `descriptor` is the concrete bindless service,
and consumers outside the rendering layer reach it only through that one
named field, never by reimplementing cache-slot bookkeeping themselves. If
`bindless-descriptor-manager.md` hasn't landed yet, land it first — this plan
doesn't stand on its own against the pre-refactor `Engine.registerBuffer`.

## Key enabling fact

The bindless descriptor set is rebuilt **every frame** from CPU-side arrays
owned by `Engine.descriptor` (post bindless-descriptor-manager move;
pre-move they're `Engine.buffer_cache`/`texture_cache`, see
`engine.zig:572-603`): they're walked and written fresh into that frame's
descriptor set. There is no persistent descriptor set holding a stale buffer
handle — so replacing the `vk.Buffer` behind a bindless slot is just "update
the array entry," not "carefully swap an in-use descriptor." This removes
most of the complexity the general Vulkan resize advice warns about
(recreating descriptor sets, staging the swap across frames). We still must
not destroy the *old* `VkBuffer`/memory while a previously-submitted command
buffer could still be reading it — `Buffer.resize` already handles that today
via `transfer()`'s `queueWaitIdle` (blocking, but this is a load-time path,
not per-frame, so a stall is acceptable).

## Design

### 1. Ownership

`AssetManager` owns exactly one `pbr_material_buffer: Buffer`, one bindless
slot (`pbr_material_buffer_slot: u32`), and tracks usage:

```zig
pbr_material_buffer: Buffer,
pbr_material_buffer_slot: u32,
pbr_material_count: u32 = 0,      // materials written so far
```

Capacity is derived (`pbr_material_buffer.size / @sizeOf(PBRMaterial.MaterialConstants)`)
rather than tracked separately, so it can't drift out of sync with the buffer.

`Objects.Model` loses `material_data_buffer` / `material_data_buffer_slot_idx`
(`scene_management/objects.zig:154,156`) and the `destroy` call in
`Model.deinit` (`objects.zig:184`) — a `Model` no longer owns any material
storage, it only holds `*Material` handles whose data lives in the shared
buffer.

### 2. Init

`AssetManager.init` (`manager.zig:131-141`) allocates the buffer up front at
some initial capacity (mirrors `VERTEX_BUFFER_SIZE`/`INDEX_BUFFER_SIZE` in
`buffer.zig:13-14` — pick e.g. `INITIAL_MATERIAL_CAPACITY = 256`), and
registers it once:

```zig
pbr_material_buffer = try PBRMaterial.createMaterialPushConstantsBuffer(engine, INITIAL_MATERIAL_CAPACITY);
pbr_material_buffer_slot = try engine.descriptor.registerBuffer(&pbr_material_buffer, 0);
```

### 3. Bindless registry: update a slot in place

This is `BindlessRegistry.updateBufferSlot` from
[bindless-descriptor-manager.md](bindless-descriptor-manager.md) — not
something this plan adds itself, just the API it depends on:

```zig
pub fn updateBufferSlot(self: *BindlessRegistry, slot: u32, buffer: *const Buffer, offset: u64) void {
    self.buffer_cache.items[slot] = .{
        .buffer = buffer.vk_buffer,
        .offset = offset,
        .range = buffer.size,
    };
}
```

Needed because `Buffer.resize` swaps `self.vk_buffer`/`memory`/`size` in
place (same `Buffer` value, new handles) — every existing bindless-slot
consumer (`Material.buffer_slot_idx`) keeps working unmodified; only the
registry's cache entry the render loop reads needs refreshing. `AssetManager`
never reaches into `buffer_cache` itself — it only calls
`engine.descriptor.updateBufferSlot(...)`, keeping the registry's internals
private to the rendering layer.

### 4. Growth-aware append, replacing the per-glTF buffer creation

New helper on `AssetManager`, called once per glTF load instead of the
`createMaterialPushConstantsBuffer`/`registerBuffer` pair at
`manager.zig:519-524`:

```zig
fn ensureMaterialCapacity(self: *AssetManager, engine: *Engine, additional: u32) !void {
    const capacity = self.pbr_material_buffer.size / @sizeOf(PBRMaterial.MaterialConstants);
    const needed = self.pbr_material_count + additional;
    if (needed <= capacity) return;

    var new_capacity = capacity;
    while (new_capacity < needed) new_capacity *|= 2; // double like ArrayList growth

    try self.pbr_material_buffer.resize(engine.getCurrentFrame().cmd_pool, new_capacity * @sizeOf(PBRMaterial.MaterialConstants));
    engine.descriptor.updateBufferSlot(self.pbr_material_buffer_slot, &self.pbr_material_buffer, 0);
}
```

`loadGLTFAsset` then:

1. Calls `try self.ensureMaterialCapacity(engine, @intCast(gltf.data.materials.len))` up front (replacing lines 519-524).
2. Uses `self.pbr_material_buffer_slot` (not a freshly-registered slot) as every
   material's `buffer_slot_idx` in `createMaterialInstance` (`manager.zig:627`).
3. Uses a **global** offset for both the `data_buffer_offset` passed into
   `MaterialResources` (`manager.zig:574`, currently `i * sizeOf(...)`) and the
   final `copyInto` (`manager.zig:636`): `(self.pbr_material_count + i) * @sizeOf(PBRMaterial.MaterialConstants)`.
4. After the material loop, bumps `self.pbr_material_count += @intCast(gltf.data.materials.len)`.

`copyInto`'s destination offset changes from always-`0` to the running
material count's byte offset, so each glTF's materials land after the
previous glTF's instead of overwriting slot 0.

### 5. Deletion/eviction — explicitly out of scope

Materials are never individually unloaded today, so there's no shrink or
free-list to design. The buffer is a bump allocator that only grows. If
`AssetManager` later needs to unload a glTF's materials, that's a separate
follow-up (would need either compaction or a free-list over fixed-size
slots) — flagging it here so it's not silently assumed away.

## Step-by-step implementation

0. Land [bindless-descriptor-manager.md](bindless-descriptor-manager.md) first — it's what puts `registerBuffer`/`updateBufferSlot` on `Engine.descriptor`. This plan's steps assume `engine.descriptor.registerBuffer`/`engine.descriptor.updateBufferSlot` already exist; it does not add them itself.
1. `manager.zig`: add `pbr_material_buffer_slot`, `pbr_material_count` fields; init the buffer + slot in `AssetManager.init` via `engine.descriptor.registerBuffer(...)`; add `ensureMaterialCapacity` (calls `engine.descriptor.updateBufferSlot(...)` after resizing).
2. `manager.zig` `loadGLTFAsset`: replace lines 519-524 (the per-glTF `createMaterialPushConstantsBuffer` + `engine.registerBuffer` pair) with the `ensureMaterialCapacity` call; change `data_buffer_offset` (line 574) and the `copyInto` offset (line 636) to use the global running offset; change `createMaterialInstance`'s `buffer_slot_idx` argument (line 627) from `loaded_gltf.material_data_buffer_slot_idx` to `self.pbr_material_buffer_slot`; bump `pbr_material_count` after the loop.
3. `scene_management/objects.zig`: remove `material_data_buffer`/`material_data_buffer_slot_idx` fields from `Model` and the `destroy` call in `Model.deinit`.
4. `AssetManager.deinit`: destroy `pbr_material_buffer` once (it's no longer per-`Model`).
5. Delete `src/resource_management/material.zig` — it's a stale, broken copy-paste of `mesh.zig` (references `Mesh`-only fields/methods on a `Material`), never imported by `manager.zig` (which correctly imports `Material` from `mesh.zig`), and would only cause confusion left in place.
6. Sanity check: load two glTFs whose combined material count crosses the initial capacity; confirm exactly one resize happens, and that materials from the *first* glTF still render correctly afterward (proves the slot update — not just the buffer content — took effect).

## Open questions

- **Initial capacity** — 256 is a guess; worth checking a couple of real asset material counts to pick something that avoids a resize on typical scenes.
- **`cmd_pool` source** — `engine.getCurrentFrame().cmd_pool` matches what `Mesh.upload` already uses for its own immediate transfer, but loading happens outside the per-frame draw loop; worth confirming that pool is valid/idle at asset-load time rather than mid-frame.
- **Sequencing with bindless-descriptor-manager** — if that plan is deferred, `engine.registerBuffer`/a bare `Engine.updateBufferSlot` could be used as a stopgap, but that reintroduces the exact coupling (resource-management code reaching past a service boundary into rendering-layer internals) the Service Locator split was meant to avoid — better to land the two together.
