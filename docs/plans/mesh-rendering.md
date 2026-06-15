# Plan: Fix 3D Mesh Rendering

**Status**: Steps 2–5 complete. Pipeline + descriptors verified clean against Vulkan validation. Steps 1 (SceneData time alignment) and 6 (MeshCmd through DrawQueue) deferred — non-blocking.
**Context**: `src/renderer/CONTEXT.md` — "Known issues / 3D mesh rendering is disabled"

## What landed

- `createMeshPipeline` set layouts → `[vk_mesh_descriptor_set_layout, vk_material_descriptor_set_layout]`
- `vk_mesh_descriptor_set` allocated with `VkDescriptorSetVariableDescriptorCountAllocateInfo` (count = 4048) so the bindless texture binding actually has slots
- `material_buffer` field added; created at setup with `colorFactors = {1,1,1,1}`; written to `vk_material_descriptor_set` binding 0
- Bindless texture array seeded at index 0 with `error_checker` so any `colorTexID = 0` sample is defined
- `draw_mesh` refreshes `current_frame.scene_data_buffer` and rewrites `vk_mesh_descriptor_set` binding 0 every frame (camera changes per frame)
- `Swapchain.recreate` now calls `deviceWaitIdle` before destroying semaphores and the old swapchain — fixes pre-existing teardown race


Meshes load correctly from `assets/meshes/basic.glb` (confirmed: `asset_loader.loadMeshes` runs in `setup()`). The problem is entirely in the render path — three interlocked pieces are commented out. They must be restored in the order below because each step is a prerequisite for the next.

---

## Step 1 — Fix `SceneData` size mismatch

**File**: `src/renderer/command.zig`

The `time` field is `f32` (4 bytes) but the shader's `SceneData` declares `float4 time` (16 bytes). The uniform buffer is undersized by 12 bytes. Fix before anything else, since the mesh shader reads this struct.

```zig
// Before
time: f32 align(4) = 0,

// After
time: @Vector(4, f32) = .{ 0, 0, 0, 0 },
```

Set only `time[0]` at the call site in `scene_manager.zig`.

---

## Step 2 — Restore the mesh descriptor layout

**File**: `src/renderer/vulkan/engine.zig`, `GlobalDescriptor.setup()`

Uncomment and fix the `// { // Mesh ... }` block (lines ~211–236). The mesh shader (`mesh.slang`) expects:

- **Set 0 binding 0**: `uniform_buffer` (SceneData) — already present as `scene_descriptor_layout`, but the mesh shader also needs bindless textures at binding 1.
- **Set 0 binding 1**: `combined_image_sampler` (variable count, `partially_bound` + `variable_descriptor_count`) — the `BindlessSceneParams.allTextures[]` array.

Restore the layout so it matches `ParameterBlock<BindlessSceneParams>`:

```zig
// In GlobalDescriptor.setup() — restore this block:
{ // Mesh: set 0 = scene data + bindless textures
    var mesh_desc_builder = try DescriptorLayoutBuilder.init(self.allocator);
    defer mesh_desc_builder.deinit();
    try mesh_desc_builder.addBinding(0, .uniform_buffer);
    try mesh_desc_builder.addBinding(1, .combined_image_sampler);
    mesh_desc_builder.bindings.items[1].descriptor_count = 4096;

    const flags: [2]vk.DescriptorBindingFlags = .{
        .{},
        .{ .partially_bound_bit = true, .variable_descriptor_count_bit = true },
    };
    const bind_flags: vk.DescriptorSetVariableDescriptorCountAllocateInfo = .{ ... };

    self.vk_mesh_descriptor_set_layout = try mesh_desc_builder.build(
        ctx,
        .{ .vertex_bit = true, .fragment_bit = true },
        .{},
        @ptrCast(&bind_flags),
    );
    self.vk_mesh_descriptor_set = try self.desc_allocator.allocate(
        ctx, self.vk_mesh_descriptor_set_layout, null,
    );
}
```

Also add `vk_mesh_descriptor_set_layout` to the `destroy()` cleanup:
```zig
ctx.device.destroyDescriptorSetLayout(self.vk_mesh_descriptor_set_layout, null);
```

> **Deferred option**: If bindless textures are not needed yet, use `SimpleSceneParams` (just the UBO) for the mesh pass as well — same as `_2d_bis`. This avoids the variable-count complexity. The mesh shader would need to be updated to `import include.scene` and use `SimpleSceneParams` instead of `BindlessSceneParams`. Color from `colorFactors` only, no texture sampling.

---

## Step 3 — Fix `createMeshPipeline()` set layout

**File**: `src/renderer/vulkan/engine.zig`, `createMeshPipeline()`

Currently the set_layouts array only contains material (set 0 in practice, but intended for set 1). Fix to match what `draw_mesh()` binds:

```zig
// Before (wrong — only 1 layout, mesh commented out):
const set_layouts = [_]vk.DescriptorSetLayout{
    // self.descriptor.vk_mesh_descriptor_set_layout,  // set 0 — was missing
    self.descriptor.vk_material_descriptor_set_layout, // set 1 — was at position 0
};

// After:
const set_layouts = [_]vk.DescriptorSetLayout{
    self.descriptor.vk_mesh_descriptor_set_layout,     // set 0: scene + textures
    self.descriptor.vk_material_descriptor_set_layout, // set 1: material
};
```

Then call it in `setup()`:
```zig
// Uncomment:
try self.createMeshPipeline();
```

---

## Step 4 — Fix `draw_mesh()` to write the scene descriptor and iterate meshes

**File**: `src/renderer/vulkan/engine.zig`, `draw_mesh()`

Two problems:

**4a. Write SceneData into the mesh descriptor set before binding.**

The `_2d_bis` pass does this inline per frame (allocates from frame descriptor allocator, writes the SceneData buffer, binds). `draw_mesh()` needs the same treatment. Before calling `cmdBindDescriptorSets`:

```zig
// Allocate a per-frame descriptor for set 0
const mesh_descriptor = try current_frame.desc_allocator.allocate(
    self.ctx, self.descriptor.vk_mesh_descriptor_set_layout, null,
);
self.descriptor.writer.clear();
try current_frame.scene_data_buffer.copyInto(self.ctx, &std.mem.toBytes(current_frame.scene_data), 0);
try self.descriptor.writer.writeBuffer(0, current_frame.scene_data_buffer, current_frame.scene_data_buffer.size, 0, .uniform_buffer);
// binding 1 (textures) left empty for now — partially_bound lets us omit them
self.descriptor.writer.updateSet(self.ctx, mesh_descriptor);
```

**4b. Replace the hardcoded `self.meshes.items[2]` with a loop.**

```zig
// Before:
const push_constant = .{ .render_matrix = ..., .vb_address = self.meshes.items[2].buffers.vertex.?.address.? };
self.ctx.device.cmdBindIndexBuffer(cmdbuf, self.meshes.items[2].buffers.index.?.vk_buffer, ...);
// ...
self.ctx.device.cmdDrawIndexed(cmdbuf, self.meshes.items[2].surfaces.items[0].count, ...);

// After:
for (self.meshes.items) |*mesh| {
    if (mesh.buffers.vertex == null or mesh.buffers.index == null) continue;
    for (mesh.surfaces.items) |surface| {
        const push_constant: Mesh.PushConstants3D = .{
            .render_matrix = current_frame.scene_data.view_proj,
            .vb_address = mesh.buffers.vertex.?.address.?,
        };
        self.ctx.device.cmdBindIndexBuffer(cmdbuf, mesh.buffers.index.?.vk_buffer, 0, .uint16);
        self.ctx.device.cmdPushConstants(cmdbuf, pipeline.layout, .{ .vertex_bit = true }, 0, @sizeOf(Mesh.PushConstants3D), @ptrCast(&push_constant));
        self.ctx.device.cmdBindDescriptorSets(cmdbuf, .graphics, pipeline.layout, 0, 1, @ptrCast(&mesh_descriptor), 0, null);
        self.ctx.device.cmdBindDescriptorSets(cmdbuf, .graphics, pipeline.layout, 1, 1, @ptrCast(&self.descriptor.vk_material_descriptor_set), 0, null);
        self.ctx.device.cmdDrawIndexed(cmdbuf, surface.count, 1, surface.start_index, 0, 0);
    }
}
```

---

## Step 5 — Uncomment `draw_mesh()` in `fillCommandBuffers()`

**File**: `src/renderer/vulkan/engine.zig`, `fillCommandBuffers()`

```zig
// Uncomment:
self.draw_mesh(cmdbuf);
```

Place it after `draw_2d_bis` and before the blit to swapchain. The draw_image is already in `color_attachment_optimal` layout at that point.

---

## Step 6 — Add a `draw_mesh` `MeshCmd` type to the DrawQueue (future)

**File**: `src/renderer/command.zig`

Currently `DrawCmd` has a `MeshCmd` variant that is unused. Once meshes render, the scene manager should push mesh draw commands instead of hardcoding them in the renderer. This follows the architecture rule: the renderer must not know which meshes to draw.

The correct flow:
```
SceneManager pushes: draw_queue.push(.{ .mesh = .{ .mesh_index = i, .transform = ... } })
Renderer reads each .mesh DrawCmd in flush() and dispatches draw_mesh() per entry
```

This step is out of scope for the initial fix but is required before the architecture is clean.

---

## Validation checklist

After completing steps 1–5:

- [ ] Build succeeds (`zig build`)
- [ ] Vulkan validation layers report no errors (run with `VK_LAYER_PATH` set)
- [ ] `basic.glb` meshes appear on screen
- [ ] Camera movement (T/D/R/S keys + mouse) moves around the meshes
- [ ] No crash when the window is resized (swapchain recreation path)
- [ ] `draw_background` (sky) still renders behind the meshes

---

## Scope boundary

This plan does NOT include:
- Bindless texture sampling (mesh surface colors only, no texture maps)
- Depth buffer / Z-testing (meshes may overdraw incorrectly)
- Per-object model matrices (all meshes rendered at world origin)
- Material PBR (metal/roughness) parameters

Those are follow-on work after the basic mesh draw is confirmed working.
