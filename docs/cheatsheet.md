# Cheatsheet

Reusable knowledge for working on this engine. Commands, conventions, and gotchas that have actually bitten us — not a tutorial.

---

## Commands

| What | Command |
|---|---|
| Build | `zig build` |
| Build + run | `zig build run` (or `make run`) |
| Run tests | `zig build test` |
| Compile shaders | Runs automatically as part of `zig build` via `tools/compile_shader.zig` (`SHADER_FOLDER = src/shaders`, only recompiles on timestamp change) |
| Force shader rebuild | `touch src/shaders/*.slang && zig build` |

**Vulkan validation layers are always on** — `VK_LAYER_KHRONOS_validation` is hardcoded in `src/core/graphics_context.zig:14`. No env var needed. Errors are routed through the debug-utils messenger callback in the same file.

---

## Conventions

### zmath (row-vector)

zmath uses **row-vector** convention. `zm.mul(A, B)` means "apply A then B".

- Correct MVP composition: `zm.mul(view, projection)` — **not** `mul(projection, view)`.
- Vectors are written `vec * matrix`, not `matrix * vec`.

See `[[feedback_zmath_convention]]`.

### Vertex layout (3D mesh)

`Data.Vertex` is 48 bytes, **scalar/std430** layout (matches `mesh.slang`):

| Field | Offset | Type |
|---|---|---|
| `pos` | 0 | `f32x3` |
| `uv_x` | 12 | `f32` |
| `normal` | 16 | `f32x3` |
| `uv_y` | 28 | `f32` |
| `col` | 32 | `f32x4` |

Indices are `u16` (`Data.Indice`). Asserted by unit tests in `src/renderer/data.zig`.

### Shader expectations (`mesh.slang`)

- Set 0 = `BindlessSceneParams` (UBO at binding 0, `Sampler2D allTextures[]` at binding 1, variable count).
- Set 1 = `MaterialParams` (UBO).
- Push constants = `PushConstants3D { render_matrix: mat4, vb_address: u64 }`.
- No vertex input state — geometry is read by dereferencing `storageBuffer.vertexBuffer[vid]` via the device address in the push constant.

---

## Vulkan gotchas

### `0xAA` everywhere = use-after-free

The Zig debug allocator overwrites freed memory with `0xAA`. If GPU sees positions of `(0xAAAAAAAA, …)` or indices of `43690` (`0xAAAA`), something was freed too early. Classic source: parsers that return slices into the input buffer (see `zgltf` below).

### Parser slice lifetimes

`zgltf` stores `glb_binary` as a **slice into the input file buffer** — it does not copy. `defer free(buffer)` after `parse(buffer)` will give `0xAA` garbage on every accessor read. Fix: retain the buffer for the loader's lifetime (`AssetLoader.file_buffers` does this). See `[[feedback_use_after_free_pattern]]`.

### Variable descriptor count needs `VkDescriptorSetVariableDescriptorCountAllocateInfo` at allocate time

If a binding is declared with `variable_descriptor_count_bit`, you must pass `VkDescriptorSetVariableDescriptorCountAllocateInfo` (with the actual count) at **allocate time**. Otherwise the effective count is 0 and any descriptor write to that binding silently does nothing. See `GlobalDescriptor.setup` mesh block.

### Swapchain recreate must `deviceWaitIdle` first

`Swapchain.recreate` waits on `deviceWaitIdle` before destroying semaphores / the old swapchain. Waiting on just the current frame's fence leaves the other in-flight frame's semaphores destroyed mid-use.

### `cmdDrawIndexed` count must match the mesh

Hardcoding the index count (e.g. `cmdDrawIndexed(cmd, 6, …)`) produces validation errors when used against a mesh that has a different surface size. Always pull from `mesh.surfaces.items[N].count` and `start_index`.

### `load_op = .load` + no depth = last-drawn-wins

All current passes use `load_op = .load` on `draw_image` and there is no depth buffer. Draw order matters: 2d_bis first, then mesh, otherwise the quad overdraws the mesh. If two meshes overlap they'll z-fight.

### `SceneData.time` size mismatch (open)

Zig declares `time: f32` (4 bytes), shader declares `float4 time` (16 bytes). UBO is undersized by 12 bytes. Benign today because `time` is last in the struct, but fix to `@Vector(4, f32)` and only write index 0.

---

## Debug techniques used in this codebase

### `[SELFTEST]` instrumentation

Pattern: load a mesh, then print first/last vertex pos, color, bounding box, index range, surface count, raw byte dump of vertex 0. Lives in `asset_loader.loadMeshes`. The `0xAA` pattern in the dump caught the zgltf use-after-free; magnitudes ≈ 1.0 on every position caught the position/normal accessor swap.

### Hand-built control meshes

`Renderer.selftest_mesh` (triangle, 3 indices) and `Renderer.cube_mesh` (24 verts / 36 indices, per-face colors) are committed in `setup()` and rendered side-by-side with whatever's under test. If the control renders and the under-test doesn't, the issue is in the data path, not the pipeline.

### Cube ground truth

`Renderer.cube_mesh` — unit cube centered at origin, 6 face colors:
- +Z blue, -Z yellow, +X red, -X cyan, +Y green, -Y magenta.

Useful when verifying winding, culling, projection orientation, or descriptor wiring.

---

## Project structure

- Single-context repo. `CONTEXT.md` at repo root, `docs/adr/` for decisions.
- Subdir `CONTEXT.md` (e.g. `src/renderer/CONTEXT.md`) documents that area's modules and known issues.
- Plans live in `docs/plans/` (e.g. `docs/plans/mesh-rendering.md`).
- Issue tracker: GitHub Issues at `HugoBroudeur/orderbook`. See `docs/agents/issue-tracker.md`.

---

## When investigating a render bug

1. Render a control next to the suspect (`selftest_mesh` + `cube_mesh` pattern).
2. Dump vertex/index data right after upload (`[SELFTEST-loader]` style).
3. Check magnitudes — all-`1.0` positions = normal accessor, all-`0xAA` = use-after-free.
4. Confirm validation layers are clean (they're always on; read stderr).
5. Verify `cmdDrawIndexed` uses `surface.count` / `surface.start_index`, not a hardcoded number.
6. Verify `cmdBindIndexBuffer` index type matches `Data.Indice` (`.uint16`).
