# Load `Material` as a Resource, the same way `Mesh` is loaded

## Context — current state is a half-finished migration

You've already started this migration by hand and it's left the tree in a
broken, doubled-up state. Worth reading in full before continuing, so the
next pass doesn't layer more on top of the same tangle.

**Three competing `Material`-shaped types exist right now:**

1. `resource_management/mesh.zig:43-45` — `pub const Material = struct { data: MaterialInstance };`, the type `Surface.material` (`mesh.zig:51`) and `Mesh.bindMaterials` (`mesh.zig:120`) actually use.
2. `resource_management/material.zig:33-58` — a *different*, Resource-shaped `Material` (`id`/`buffer`/`source`/`pbr` + `init`/`getId`/`setDataSource`/`load`/`unload`/`interface`), which is what `manager.zig:23` imports and what `self.load(Material, ...)` (`manager.zig:550`) actually constructs.
3. `engine/graphics/materials.zig:33` — `PBRMaterial` (pipelines, `MaterialConstants`, `MaterialResources`, `createMaterialInstance`) — this one is correct and shouldn't change.

Since (1) and (2) are different types, `Mesh.bindMaterials(materials: []const *mesh.Material)` and `self.load(Material, ...)` (which produces a `*material.Material`) are **not interchangeable** — this alone won't compile once both paths are exercised.

**`resource_management/material.zig` also redeclares `PBRMaterial` and `MaterialPass`** (`material.zig:12-30`) as bare CPU-side structs with different field shapes than the real ones in `engine/graphics/materials.zig` — no `MaterialConstants` sub-type, no `MaterialResources`, no offset/size comptime asserts against the shader layout. `bindless.zig:14` imports *this* wrong `PBRMaterial` (`@import("../../resource_management/material.zig").PBRMaterial`) and then does `@sizeOf(PBRMaterial.MaterialConstants)` (`bindless.zig:257`) — `MaterialConstants` doesn't exist on that struct, so `Registry.ensureMaterialCapacity`/`createMaterialBuffer` don't compile as written.

**`resource.zig` doesn't export `Material` at all**, and its `Mesh` export is subtly wrong:

```zig
// resource.zig:6
pub const Mesh = @import("mesh.zig");
```

This binds `Resource.Mesh` to the whole `mesh.zig` file-as-namespace, not to
`mesh.zig`'s `Mesh` struct. `objects.zig:75,141` do `*Resource.Mesh` expecting
the struct; `objects.zig:146` does `*Resource.Material`, which doesn't exist
at all (this is the `resource_management.resource has no member named
'Material'` build error from before).

**The shared material buffer (`engine.descriptor.pbr_material_buffer`,
landed via [bindless-descriptor-manager.md](bindless-descriptor-manager.md) +
[shared-material-buffer.md](shared-material-buffer.md)) is wired up but
never actually used.** `manager.zig:540` calls `engine.descriptor.ensureMaterialCapacity(...)`
once per glTF, but nothing ever calls `copyInto` on
`engine.descriptor.pbr_material_buffer` or increments
`engine.descriptor.pbr_material_count` — meanwhile the **old** per-glTF path
is still fully wired and doing the real work in parallel: `manager.zig:515`
creates a brand new `PBRMaterial.createMaterialPushConstantsBuffer` per
glTF, registers it as its own bindless slot (`:520`), and batch-writes
`scene_material_constants` into *that* buffer (`:636`) — completely
independent of the new shared buffer. Right now there are two buffers doing
the job, one dead, one used by the actual materials.

None of this is a criticism of the direction — the shared buffer, the
registry, and the `self.load(Material, ...)` call site are all the right
pieces. They just haven't been connected to each other yet, and the old path
was never removed. This plan is the removal + connection.

## Target design

Mirror `Mesh` exactly — same five `Resource` vtable methods, same shape.
Compare side by side:

| | `Mesh` (working, today) | `Material` (target) |
|---|---|---|
| Struct fields | `id`, `buffers: MeshBuffers`, `surfaces`, `source` | `id`, `data: MaterialInstance`, `source` |
| `init(id)` | sets `id` only | sets `id` only |
| `setDataSource` | stores `source` | stores `source` |
| `load(engine)` | parses `source.gltf`, builds its own vertex/index buffers, calls `upload` | parses `source.gltf`, **registers** on the shared buffer to get a slot id, calls `upload` |
| `upload(engine, ...)` | `vkCmdCopyBuffer`s parsed vertex/index bytes into the buffers it just created | `copyInto`s the parsed `MaterialConstants` into the shared buffer at the offset its registered id gives it |
| `unload(engine)` | destroys its own buffers | no-op (see "Deletion/eviction — explicitly out of scope" in shared-material-buffer.md — the shared buffer is a bump allocator, nothing to free per-material) |
| Owns a GPU buffer? | yes, its own | no — writes into `engine.descriptor.pbr_material_buffer` at the offset its registered `material_idx` gives it |

The split matters: **registering** a material (reserving a slot in the
shared buffer, growing it if needed) is a bindless-registry concern — the
same shape as `registerTexture`/`registerBuffer`/`registerCubemap`, which
all just hand back a slot id and touch nothing else. **Uploading** the
actual bytes into that slot is the resource's own job, same as `Mesh`
uploading its own vertex/index bytes after creating its own buffers. Folding
both into one call (as an earlier draft of this plan did) blurs that line —
`Material.load` should ask the registry for an id, then write its own data
into the slot it was given, not hand the registry raw bytes to place.

`Material` does **not** get its own `buffer` field or its own `pbr` field
that outlives `load()` — once its `MaterialConstants` are written into the
shared buffer, the only thing anything needs afterward is `data:
MaterialInstance` (pipeline pointer + `buffer_slot_idx` + `material_idx`),
exactly like `Mesh` doesn't keep its parsed vertices/indices around after
upload.

### Texture index resolution — how a material finds its bindless texture ids

Two independent write-ups of this exact bindless pattern agree on the
GPU-side shape:

- [Arseny Kapoulkine — "Writing an efficient Vulkan renderer" (zeux.io, Feb 2020)](https://zeux.io/2020/02/27/writing-an-efficient-vulkan-renderer/),
  "Bindless descriptor designs": *"All material constants for all materials
  in the scene will reside in one large storage buffer"*, and *"Each
  material in the material data will have an index into this [texture]
  array instead of texture descriptor; the index will be part of the
  material data"* — with the shader-side `MaterialData` struct storing raw
  `uint albedoTexture` / `normalTexture` / `roughnessTexture` fields, read
  as `materialTextures[md.albedoTexture]`.
- [vkguide.dev — "Material System" (GPU-driven rendering chapter)](https://vkguide.dev/docs/gpudriven/material_system/):
  the shared `materialDataBuffer` is filled by loading materials **in
  sequence**, each getting an index corresponding to its position in the
  buffer; scene draw data stores a `materialIndex` that's used to index into
  it.

Neither source spells out the loading-order mechanics (that's called out
explicitly in the zeux.io piece as a renderer-specific decision), but the
GPU-side shape they agree on has one hard consequence: **a material's
`_tex_id` fields must already be final bindless indices by the time the
material record is written** — a texture can't get its slot *after* a
material referencing it has already been uploaded. Since bindless texture
slots come from `engine.descriptor.registerTexture`, which must run once per
unique glTF texture (not once per material reference, or shared textures
burn a slot every time they're re-referenced), texture registration has to
happen as its own pass over `gltf.data.textures`, finished *before* any
material tries to resolve a texture reference. `manager.zig:522-535`
already does exactly this, into a local `bindless_slots: []u32` array
(index = glTF texture index, value = bindless slot) — that part of the
existing code was already correct; what's missing is a way for
`Material.load(engine)` to read it, since `load` only receives `*Engine`,
not the `AssetManager`/`bindless_slots` local it was built in.

`Resource.DataSource` is how every other piece of load-time context reaches
a resource's `load()` (see `Mesh.load` reading `source.gltf.data`/`.idx`
today) — so the fix is to carry the already-resolved array the same way,
not to have `Material.load` try to re-derive or re-register anything itself:

```diff
  gltf: struct {
      data: *Gltf,
      idx: u32,
+     bindless_slots: []const u32 = &.{},
  },
```

This field does not exist yet — it's new, added by this plan. Defaulted, so
the existing `Mesh` construction site (`manager.zig:644`,
`.gltf = .{ .data = &gltf, .idx = ... }`) doesn't need to change; only the
material construction site (shown below) sets it, passing the same
`bindless_slots` slice `loadGLTFAsset` already builds today.

### `resource_management/material.zig` — final shape

```zig
const std = @import("std");
const Engine = @import("../engine/vulkan/engine.zig");
const Resource = @import("resource.zig").Resource;
const materials = @import("../engine/graphics/materials.zig");
const MaterialInstance = materials.MaterialInstance;
const MaterialPass = materials.MaterialPass;
const MaterialConstants = materials.PBRMaterial.MaterialConstants;

pub const Material = struct {
    id: []const u8,
    source: Resource.DataSource = undefined,
    data: MaterialInstance = undefined,

    pub fn interface(self: *Material) Resource {
        return Resource.interface(self);
    }

    pub fn init(id: []const u8) !Material {
        return .{ .id = id };
    }

    pub fn getId(self: *const Material) []const u8 {
        return self.id;
    }

    pub fn setDataSource(self: *Material, source: Resource.DataSource) void {
        self.source = source;
    }

    pub fn load(self: *Material, engine: *Engine) !void {
        const src = switch (self.source) {
            .gltf => |s| s,
            else => @panic("Not implemented"),
        };
        const gltf_material = src.data.data.materials[src.idx];

        const constants: MaterialConstants = .{
            .color_factors = gltf_material.metallic_roughness.base_color_factor,
            .metal_rough_factors = .{ gltf_material.metallic_roughness.metallic_factor, gltf_material.metallic_roughness.roughness_factor, 0, 0 },
            .emissive_factor = .{ gltf_material.emissive_factor[0], gltf_material.emissive_factor[1], gltf_material.emissive_factor[2], gltf_material.emissive_strength },
            .transmission_factor = gltf_material.transmission_factor,
            .color_tex_id = resolveTexSlot(src.bindless_slots, gltf_material.metallic_roughness.base_color_texture),
            .metal_rough_tex_id = resolveTexSlot(src.bindless_slots, gltf_material.metallic_roughness.metallic_roughness_texture),
            .normal_tex_id = resolveTexSlot(src.bindless_slots, gltf_material.normal_texture),
            .occlusion_tex_id = resolveTexSlot(src.bindless_slots, gltf_material.occlusion_texture),
            .emissive_tex_id = resolveTexSlot(src.bindless_slots, gltf_material.emissive_texture),
            .transmission_tex_id = resolveTexSlot(src.bindless_slots, gltf_material.transmission_texture),
            .cube_tex_id = 0,
        };

        const pass_type: MaterialPass = if (gltf_material.alpha_mode == .blend) .Transparent else .MainColor;

        const material_idx = try engine.descriptor.registerMaterial();
        self.data = engine.pbr_material.createMaterialInstance(pass_type, material_idx, engine.descriptor.pbr_material_buffer_slot);

        try self.upload(engine, constants);
    }

    fn upload(self: *Material, engine: *Engine, constants: MaterialConstants) !void {
        try engine.descriptor.pbr_material_buffer.copyInto(
            std.mem.asBytes(&constants),
            self.data.material_idx * @sizeOf(MaterialConstants),
        );
    }

    pub fn unload(self: *Material, engine: *Engine) void {
        _ = self;
        _ = engine;
    }

    fn resolveTexSlot(bindless_slots: []const u32, tex_info: anytype) u32 {
        const info = tex_info orelse return 0;
        return bindless_slots[info.index];
    }
};
```

Note `load` reaches the shared buffer **only** through `engine.descriptor` —
same Service Locator boundary used in the previous two plans. `Material`
never touches a `buffer_cache` array or a raw `Buffer` itself, and never
picks its own offset — it always writes at `self.data.material_idx`, the id
the registry handed back.

### `bindless.zig` — new `registerMaterial` (registration only), and the import fix

Mirrors `registerTexture`/`registerBuffer`/`registerCubemap`: reserves a
slot and returns its id, does **not** touch buffer contents. Growing the
buffer is still its job (that's registry-owned capacity, same as before),
writing into the slot once reserved is not:

```zig
pub fn registerMaterial(self: *Registry) !u32 {
    try self.ensureMaterialCapacity(1);
    const idx = self.pbr_material_count;
    self.pbr_material_count += 1;
    return idx;
}
```

And fix the import this depends on — `bindless.zig:14` currently points at
the wrong (soon-to-be-deleted) `PBRMaterial`:

```diff
- const PBRMaterial = @import("../../resource_management/material.zig").PBRMaterial;
+ const PBRMaterial = @import("../graphics/materials.zig").PBRMaterial;
```

### `resource.zig` — export both resource types correctly

```diff
- pub const Mesh = @import("mesh.zig");
+ pub const Mesh = @import("mesh.zig").Mesh;
+ pub const Material = @import("material.zig").Material;
```

### `mesh.zig` — drop the duplicate `Material`, import the real one

```diff
- pub const Material = struct {
-     data: MaterialInstance,
- };
+ const Material = @import("material.zig").Material;
```

(`Surface.material: ?*Material` and `Mesh.bindMaterials` keep compiling
unchanged — they were already using the name `Material`, it now resolves to
the one real type instead of the local stand-in.)

### `manager.zig` `loadGLTFAsset` — material section shrinks to this

Replacing the entire block from the per-glTF buffer creation
(`manager.zig:515`) through the end of the material `for` loop (`:638`):

```zig
try engine.descriptor.ensureMaterialCapacity(@intCast(gltf.data.materials.len));

var local_materials: std.ArrayList(*Material) = try .initCapacity(self.allocator, gltf.data.materials.len);
defer local_materials.deinit(self.allocator);

for (gltf.data.materials, 0..) |gltf_material, material_idx| {
    const name = gltf_material.name orelse std.fmt.allocPrint(self.allocator, "material_idx_{}", .{material_idx}) catch "";

    const handle = try self.load(Material, name, .{ .gltf = .{ .data = &gltf, .idx = @intCast(material_idx), .bindless_slots = bindless_slots } });
    local_materials.appendAssumeCapacity(handle.get().?);

    try model.materials.put(self.allocator, name, handle.get().?);
}
```

And the mesh loop's `bindMaterials` call (`manager.zig:645`) switches from
the old pool slice to this local, glTF-scoped one:

```diff
- handle.get().?.bindMaterials(self.pool._materials.items[initial_material_index..]);
+ handle.get().?.bindMaterials(local_materials.items);
```

`try engine.descriptor.ensureMaterialCapacity(...)` up front is optional
(`registerMaterial` already calls it per-material) but keeps growth to at
most one resize per glTF instead of up to one per material when a whole
batch pushes the buffer past capacity — worth keeping for that reason alone.

## Cleanup that falls out of this (delete, don't leave commented)

- `manager.zig:392,395` — `initial_material_index` and the
  `self.pool._materials.ensureTotalCapacity` call — dead once materials are
  ref-counted through `self.load`/`ref_pool` like meshes already are.
- `ResourceManager._materials: std.ArrayList(*Material)`
  (`manager.zig:70,89,109`) — same reasoning; meshes have no equivalent
  list, materials shouldn't either.
- `manager.zig:751-772` `parseTexture` — replaced by the inline
  `resolveTexSlot` helper in `material.zig`; the `material_resources`/
  `image_field`/`sampler_field` params were already dead (everything they
  wrote into was commented out).
- `engine/graphics/materials.zig:67-83` `PBRMaterial.MaterialResources` —
  only ever constructed by the code this plan deletes; nothing else builds
  one.
- `Objects.Model.material_data_buffer` / `material_data_buffer_slot_idx`
  (`objects.zig:154,156`) and the `destroy` call in `Model.deinit`
  (`objects.zig:184`) — per the shared-material-buffer plan, `Model` no
  longer owns a buffer.
- `resource_management/material.zig:12-30`'s local `PBRMaterial`/
  `MaterialPass` — replaced by importing the real ones from
  `engine/graphics/materials.zig` (see above).

## Step-by-step

1. Fix `resource.zig`'s exports (`Mesh`, add `Material`); add `bindless_slots`
   to `DataSource.gltf` — `material.zig` depends on both.
2. Rewrite `resource_management/material.zig` to the target shape above —
   delete the local `PBRMaterial`/`MaterialPass`, delete the leftover
   `Mesh`-copy-paste fragments (`unload` currently calls `self.buffers.destroy`/
   `self.surfaces.deinit`, which don't exist on `Material`; `loadMeshData` at
   the bottom of the file is a whole duplicated `Mesh` method that doesn't
   belong here at all).
3. `mesh.zig`: drop the local `Material` struct, import it from `material.zig`.
4. `bindless.zig`: fix the `PBRMaterial` import; add `registerMaterial`.
5. `manager.zig`: replace the material section in `loadGLTFAsset` as shown
   (this is also where the existing `bindless_slots` local, already built at
   `manager.zig:522-535`, gets passed into `.gltf = .{ ..., .bindless_slots = bindless_slots }`);
   delete `parseTexture`, `initial_material_index`, `ResourceManager._materials`
   and its init/deinit lines.
6. `objects.zig`: remove `material_data_buffer`/`material_data_buffer_slot_idx`
   fields and the `destroy` call.
7. `engine/graphics/materials.zig`: delete `MaterialResources`.
8. `zig build`, then load a glTF with multiple materials (some sharing
   textures, at least one using `alpha_mode: BLEND` to exercise the
   transparent pass) and confirm it renders like it did before this file
   started diverging — colors, textures, and transparency all correct is the
   signal that `bindless_slots` threading and the shared-buffer offsets are
   both right.

## Open questions

- **Resource id collisions across glTF files** — `self.load(Material, name,
  ...)` keys purely on `name` in the global `ref_pool`; two different glTFs
  with a same-named material (e.g. both have `"Material.001"`) will collide
  and the second file silently gets the first file's material. This is a
  pre-existing property of `self.load`/`ref_pool` that `Mesh` already has
  today too (not new to this plan) — worth fixing once, for both resource
  types together, rather than solving it only for `Material` here.
- **Per-material `copyInto` vs one batched write** — the old code did a
  single `copyInto` for the whole glTF's materials (`manager.zig:636`); the
  new path does one small `copyInto` per material inside `Material.upload`.
  Matches how `Mesh.upload` already uploads itself independently per
  instance, and keeps `Material.load`/`upload` self-contained, but it's
  strictly more `vkMapMemory` calls for a multi-material glTF. Not worth
  batching back up unless it shows up in profiling.
