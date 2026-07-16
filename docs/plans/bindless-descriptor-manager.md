# Extract the bindless registry into its own descriptor-set-management module

## Context

Today the bindless machinery is spread across `Engine` itself, in three
pieces:

1. **`GlobalDescriptor`** (`engine.zig:58-98`) — a private struct holding the
   `DescriptorAllocator`/`DescriptorWriter` pair, the compute-image set/layout,
   and the global bindless set layout. `Engine` holds one as `descriptor:
   GlobalDescriptor` (`engine.zig:112`).
2. **Six loose cache fields directly on `Engine`** (`engine.zig:147-152`):
   `texture_cache`/`_count`, `buffer_cache`/`_count`, `cubemap_cache`/`_count`,
   plus `registerTexture`/`registerBuffer`/`registerCubemap`
   (`engine.zig:942-976`) that append to them.
3. **`setupDescriptors`** (`engine.zig:311-391`) builds the two layouts/sets
   above, and the **per-frame block** (`engine.zig:553-606`) rebuilds the
   frame's descriptor set from the three caches every frame via raw
   `vk.WriteDescriptorSet` construction inlined in the draw path.

`descriptor.zig` already holds the reusable low-level primitives
(`DescriptorAllocator`, `LayoutBuilder`, `DescriptorWriter`) — those are
generic and correctly separated already; this plan doesn't touch them. What's
missing is a home for the *engine-specific, bindless-specific* logic that
currently leaks into `Engine` itself.

**External call sites that reach into `engine.descriptor.*` directly** (not
through `registerX`), which must keep working after the move:
- `materials.zig:116` — reads `vk_global_descriptor_set_layout` to build a
  pipeline layout.
- `effects.zig:77` — reads `draw_image_descriptor_layout` for the compute
  pipeline layout.
- `skybox.zig:107,178-181` — allocates its *own* descriptor set off
  `vk_global_descriptor_set_layout`, then writes/updates it directly via
  `engine.descriptor.writer`/`.desc_allocator`.

**Bug noticed in passing, not part of this plan**: `cubemap_cache`/
`registerCubemap` populate a cache that the per-frame rebuild never writes
into a descriptor (binding 1 — "Cube Textures" — gets no write at
`engine.zig:553-606`, only bindings 0/2/3 do). So cubemap textures registered
this way don't currently bind to anything. This move should preserve that
behavior exactly (pure refactor) — flagging it here so it's not mistaken for
new breakage, and so it can be picked up as its own fix later if wanted.

The prior [shared-material-buffer plan](shared-material-buffer.md) needs an
`updateBufferSlot`-style method to exist somewhere; this module is that
somewhere.

## Goal

One module owns: the bindless registries (texture/buffer/cubemap caches +
counts), the global descriptor-set layout/allocation, and the per-frame
descriptor-set rebuild — so `Engine` stops carrying six loose cache fields
and stops inlining ~50 lines of `WriteDescriptorSet` plumbing in its draw
path.

## Design

### New file: `src/engine/vulkan/bindless.zig`

A `BindlessRegistry` struct that folds in everything currently named
`GlobalDescriptor` plus the three caches:

```zig
pub const BindlessRegistry = struct {
    allocator: std.mem.Allocator,
    desc_allocator: DescriptorAllocator,
    writer: DescriptorWriter,
    is_initialised: bool = false,

    draw_image_descriptor: vk.DescriptorSet = undefined,
    draw_image_descriptor_layout: vk.DescriptorSetLayout = undefined,
    vk_global_descriptor_set_layout: vk.DescriptorSetLayout = undefined,

    texture_cache_count: u32 = 0,
    buffer_cache_count: u32 = 0,
    cubemap_cache_count: u32 = 0,
    texture_cache: std.ArrayList(vk.DescriptorImageInfo),
    buffer_cache: std.ArrayList(vk.DescriptorBufferInfo),
    cubemap_cache: std.ArrayList(vk.DescriptorImageInfo),

    pub fn init(allocator, ctx) !BindlessRegistry { ... }       // GlobalDescriptor.init, moved
    pub fn destroy(self, ctx) void { ... }                       // GlobalDescriptor.destroy + 3 cache .deinit()s

    pub fn setupComputeImageSet(self, engine: *Engine) !void     // engine.zig:312-324, moved
    pub fn setupGlobalSet(self, engine: *Engine) !void           // engine.zig:325-373, moved

    pub fn registerTexture(self, image, sampler) !u32            // engine.zig:943-952, moved verbatim
    pub fn registerBuffer(self, buffer, offset) !u32              // engine.zig:955-964, moved verbatim
    pub fn registerCubemap(self, image, sampler) !u32             // engine.zig:967-976, moved verbatim
    pub fn updateBufferSlot(self, slot: u32, buffer: *const Buffer, offset: u64) void  // NEW — overwrite buffer_cache.items[slot] in place, needed by shared-material-buffer plan

    pub fn writeFrameDescriptorSet(
        self,
        ctx: *const GraphicsContext,
        frame_descriptor: *DescriptorAllocator,
        scene_data_buffer: Buffer,
    ) !vk.DescriptorSet                                          // engine.zig:559-603, moved + parameterized
};
```

`writeFrameDescriptorSet` takes the frame's `DescriptorAllocator` and
`scene_data_buffer` as parameters instead of reaching into `current_frame`
itself, so `bindless.zig` doesn't need to depend on `frames.zig` — it stays a
leaf module.

### `Engine` changes

- `descriptor: GlobalDescriptor` → `descriptor: BindlessRegistry`. **Keep the
  field name `descriptor`** — `materials.zig`, `effects.zig`, `skybox.zig`
  all already write `engine.descriptor.<field>`; renaming the field buys
  nothing here and would touch three unrelated files.
- Remove the six `texture_cache*`/`buffer_cache*`/`cubemap_cache*` fields
  from `Engine` (now live inside `descriptor`), and their init/deinit lines
  (`engine.zig:165-167`, `210-212`).
- `setup()`: `self.descriptor = try BindlessRegistry.init(...)`, then
  `try self.descriptor.setupComputeImageSet(self)` and
  `try self.descriptor.setupGlobalSet(self)`, replacing the call to
  `setupDescriptors` — which is deleted (it's now redundant with the new
  module's own name/methods).
- Per-frame block (`engine.zig:553-606`) shrinks to:
  ```zig
  try current_frame.scene_data_buffer.copyInto(&std.mem.toBytes(current_frame.scene_data), 0); // unchanged, not a descriptor concern
  current_frame.descriptor_set = try self.descriptor.writeFrameDescriptorSet(
      self.ctx, &current_frame.frame_descriptor, current_frame.scene_data_buffer,
  );
  ```
- Delete the top-level `Engine.registerTexture`/`registerBuffer`/
  `registerCubemap` wrapper functions (`engine.zig:942-976`) rather than
  keeping them as forwarding shims — see call-site update below.

### Call sites to update

- `resource_management/manager.zig:538` — `engine.registerBuffer(...)` →
  `engine.descriptor.registerBuffer(...)`
- `resource_management/manager.zig:543,547` — `engine.registerTexture(...)` →
  `engine.descriptor.registerTexture(...)`
- The `ensureMaterialCapacity` helper from the shared-material-buffer plan
  should call `engine.descriptor.updateBufferSlot(...)`, not a bare
  `engine.updateBufferSlot(...)` (that plan predates this one and hadn't been
  implemented yet — this changes its target by one path segment).

No changes needed in `materials.zig`/`effects.zig`/`skybox.zig` — they only
ever read fields on `engine.descriptor`, which keeps the same name and the
same field set.

## Step-by-step

1. Create `src/engine/vulkan/bindless.zig`; move `GlobalDescriptor`'s body in
   as `BindlessRegistry`, plus the six cache fields.
2. Move `registerTexture`/`registerBuffer`/`registerCubemap` in as methods;
   add `updateBufferSlot`.
3. Split `setupDescriptors` into `setupComputeImageSet`/`setupGlobalSet`
   methods on the new type; delete the old free function on `Engine`.
4. Add `writeFrameDescriptorSet`; move the per-frame block's
   `WriteDescriptorSet` construction into it.
5. Update `Engine`: retype `descriptor`, remove the six cache fields and
   their init/deinit lines, shrink the per-frame block to the two-line call
   above, delete the three wrapper functions.
6. Update the three call sites in `manager.zig`.
7. `zig build` — the module already has unrelated in-progress build errors
   (see prior session), so this is a smoke check for *new* breakage from the
   move, not a guarantee of a clean build.
8. Runtime smoke test: load a glTF with textures and at least one material,
   confirm it still renders — exercises `registerTexture`, `registerBuffer`,
   and `writeFrameDescriptorSet` together in one pass.

## Open questions

- **Cubemap dead-binding bug** — fix now or leave for a separate pass?
  Recommend leaving it: this plan is a pure move, easier to review with zero
  behavior change baked in.
- **Naming** — `BindlessRegistry` vs. keeping `GlobalDescriptor` vs.
  `DescriptorManager`. Leaning `BindlessRegistry`: "global descriptor"
  undersells what it now owns, and "descriptor manager" collides
  conceptually with the already-generic primitives in `descriptor.zig`.
