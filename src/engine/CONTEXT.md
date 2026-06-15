# Renderer

The rendering layer of the engine. Provides a backend-agnostic abstraction over Vulkan and SDL3 GPU, with shared interfaces for cameras, meshes, commands, and stats. The active backend is selected at compile time via `backend.zig`.

On Linux the default backend is **Vulkan**. The active entry point is `src/layers/sandbox_vulkan.zig` → `renderer/vulkan/engine.zig`.

---

## Core (shared abstractions)

| File | What it does |
|---|---|
| `backend.zig` | Selects the active rendering backend (Vulkan or SDL) and exposes factory functions for creating backend-specific APIs. |
| `interfaces.zig` | Virtual table interfaces that backend implementations must satisfy: Asset, Batcher, Buffer, GPU, Pipeline, RenderPass, Renderer2D, Sampler, Texture. |
| `camera.zig` | Orthographic and perspective camera with view/projection matrix computation. |
| `command.zig` | 2D draw command queue — queues quad, textured quad, and filled quad draw calls for batched submission. Also owns `SceneData` (view/proj/view_proj + lighting) set by SceneManager each frame. |
| `mesh.zig` | Generic mesh container holding vertex and index lists; backend-agnostic. |
| `data.zig` | Shared vertex data types (Quad, PositionTextureVertex, ViewProj) and shader data definitions used by both backends. |
| `gfx.zig` | Backend-agnostic graphics API compatibility wrapper. |
| `compute_effect.zig` | Represents a compute shader pipeline with push constants for GPU compute dispatch. |
| `stats.zig` | Frame statistics collector — tracks draw calls, vertex count, FPS, and per-stage timing. |

---

## SDL backend (`sdl/`)

| File | What it does |
|---|---|
| `gpu.zig` | SDL3 GPU device init, swapchain configuration, and command buffer management. |
| `renderer.zig` | High-level renderer manager: window setup, ImGui integration, uniform buffer management. |
| `engine.zig` | Full 2D rendering pipeline: multi-pass (demo, 2D, UI), texture sampling, batching. |
| `batcher.zig` | Batches 2D quad draw commands into vertex/index buffer pools for efficient GPU submission. |
| `pipeline.zig` | Creates SDL graphics pipelines from vertex/fragment shaders with configurable vertex input. |
| `pass.zig` | `RenderPass` and `CopyPass` wrappers for recording SDL GPU render and copy commands. |
| `buffer.zig` | SDL GPU buffer allocation and data transfer utilities (vertex, index, transfer buffers). |
| `shader.zig` | Loads SPIR-V shaders for SDL with stage reflection for buffer layout. |
| `texture.zig` | Wraps SDL GPU textures with surface ownership and fragment shader binding. |
| `sampler.zig` | Creates texture samplers with linear or nearest-neighbor filtering and edge clamping. |
| `swapchain.zig` | Manages SDL3 swapchain images, present modes, and frame synchronization. |
| `asset.zig` | Loads JPG images via SDL3 I/O and converts them to RGBA for GPU upload. |
| `impl.zig` | Aggregates all SDL backend implementations into a single module. |

---

## Vulkan backend (`vulkan/`)

| File | What it does |
|---|---|
| `gpu.zig` | Vulkan device and instance setup, swapchain configuration, and command buffer management. |
| `renderer.zig` | High-level Vulkan renderer manager: window setup, ImGui integration, uniform management. |
| `engine.zig` | Full 2D Vulkan renderer with descriptor management, frame overlap, and multi-pass rendering. |
| `batcher.zig` | Batches 2D quad draw commands into vertex/index buffer pools for Vulkan submission. |
| `pipeline.zig` | Creates Vulkan graphics and compute pipelines: layout, shader stages, vertex input. |
| `render_pass.zig` | Vulkan render pass creation with attachment descriptions and subpass configuration. |
| `descriptor.zig` | Descriptor set allocation, layout construction, and write management for shader resources. |
| `buffer.zig` | Vulkan buffer allocation with memory management, CPU-GPU sync, and device address support. |
| `image.zig` | Vulkan image allocation, image views, and GPU-side samplers. |
| `shader.zig` | Loads SPIR-V shaders with stage reflection and pipeline shader stage info generation. |
| `sampler.zig` | Creates Vulkan samplers with configurable filtering and address modes. |
| `mesh.zig` | Vulkan mesh with vertex/index GPU buffers and upload via command buffers. |
| `asset_loader.zig` | Loads GLTF/GLB model files and creates Vulkan mesh buffers from the parsed data. |
| `frames.zig` | Per-frame synchronization primitives (fences, semaphores, image views) for frame overlap. |
| `framebuffer.zig` | Vulkan framebuffers wrapping swapchain images for use as render pass attachments. |
| `command_pool.zig` | Vulkan command pool management and immediate command submission. |
| `swapchain.zig` | Vulkan swapchain lifecycle and frame image management. |
| `impl.zig` | Aggregates all Vulkan backend implementations into a single module. |

---

## Shaders (`src/shaders/`)

All shaders are written in **Slang** and compiled to SPIR-V (`.spv`). Recompile with `slangc`.

Shared type definitions live in `src/shaders/include/scene.slang` and are imported with `import include.scene;`.

### `include/scene.slang` — shared types

| Type | Purpose |
|---|---|
| `SceneData` | Per-frame camera + lighting uniform: `view`, `proj`, `viewproj` (4x4), `ambientColor`, `sunlightDirection`, `sunlightColor`, `time` (all float4) |
| `GLTFMaterialData` | Per-material data: `colorFactors` (float4) |
| `SimpleSceneParams` | Scene descriptor for non-textured passes: just `ConstantBuffer<SceneData>` |
| `BindlessSceneParams` | Full bindless scene descriptor: `ConstantBuffer<SceneData>` + `Sampler2D allTextures[]` |
| `BoundSceneParams` | Non-bindless alternative: `ConstantBuffer<SceneData>` + explicit `colorTex`/`metalRoughTex` |
| `MaterialParams` | Material descriptor for mesh pass: `ConstantBuffer<GLTFMaterialData>` |

### Shader inventory

| File | Pipeline | Pass | Bindings |
|---|---|---|---|
| `triangle.slang` / `demo.spv` | `.triangle` | Demo fullscreen triangle (no vertex input) | VS: `ConstantBuffer<{proj_matrix}>` at register(b0, space1) |
| `2d.slang` / `2d.spv` | `._2d` | 2D sprite batcher (atlas texture) | Push constants: `StorageBuffer{Scale2D+Translate2D, Vertex*}`. Set 0 binding 0: `uvTexture`, binding 1: `checkerTexture` |
| `2d_bis.slang` / `2d_bis.spv` | `._2d_bis` | 3D-positioned 2D geometry (MVP transform) | Push constants: `StorageBuffer{render_matrix 4x4, Vertex*}`. Set 0: `ParameterBlock<SimpleSceneParams>` (just SceneData) |
| `mesh.slang` / `mesh.spv` | `.mesh` | Full 3D GLTF mesh (bindless textures) — **DISABLED** | Push constants: `StorageBuffer{render_matrix 4x4, Vertex*}`. Set 0: `ParameterBlock<BindlessSceneParams>` (SceneData + allTextures[]). Set 1: `ParameterBlock<MaterialParams>` |
| `sky.slang` / `sky.spv` | `.compute` | Background sky/stars (compute) | Set 0 binding 0: `RWTexture2D<float4> image` (write-only) |
| `compute.slang` | — | Debug gradient (not in active use) | Set 0 binding 0: `RWTexture2D<float4> image` |
| `texture_quad.slang` | SDL `.solid` | SDL backend only | SDL uniform buffer + sampler |

### Push constants layout (Vulkan)

Both `2d_bis` and `mesh` shaders use `PushConstants3D`:

```zig
// mesh.zig
pub const PushConstants3D = struct {
    render_matrix: zm.Mat,          // 64 bytes — maps to StorageBuffer.uniforms.render_matrix
    vb_address: vk.DeviceAddress,   // 8 bytes  — maps to StorageBuffer.vertexBuffer (GPU pointer)
};
```

The shader accesses vertices by dereferencing `storageBuffer.vertexBuffer[vertexID]`. No vertex input state is declared; geometry comes entirely from the device-address pointer.

### Vertex formats

| Use | Zig type | Layout |
|---|---|---|
| 2D sprite (batcher) | `Data.Quad.Vertex` | pos(f32x2), uv(f32x2), col(f32x4) — 32 bytes |
| 3D GLTF mesh | `Data.Vertex` | pos(f32x3), uv_x(f32), normal(f32x3), uv_y(f32), col(f32x4) — 48 bytes |

---

## Frame data flow (Vulkan)

```
CameraSystem.update()
  → ECS Camera.PerspectiveCamera: pos, look_at, fov updated

SceneManager.render()  [called from SandboxVulkanLayer.onUpdate()]
  → beginScene():
      reads PerspectiveCamera from ECS
      calls camera.setViewport(window_size)  → recomputes view/proj/mvp
      builds SceneData { view, proj, view_proj }
      calls draw_queue.setSceneData(scene_data)     ← stores in DrawQueue.scene_data

  → push draw commands (quad, quad_fill, etc.) into draw_queue

  → endScene():
      calls draw_queue.submit()
      → engine.flush(draw_queue)

Renderer2D.flush(draw_queue)
  → copies draw_queue.scene_data into current_frame.scene_data
  → batcher.begin() / push each DrawCmd / batcher.end()
  → draw(batches)

Renderer2D.draw(batches)
  → uploads batcher vertex/index data to GPU buffer
  → fillCommandBuffers()

Renderer2D.fillCommandBuffers()
  1. draw_background(cmdbuf)         [compute: sky.spv, set 0 = draw_image storage]
  2. draw_2d_bis(cmdbuf)             [graphics: 2d_bis.spv, push = PushConstants3D, set 0 = scene_data UBO]
  3. [DISABLED] draw_mesh(cmdbuf)    [graphics: mesh.spv, push = PushConstants3D, set 0 = scene+textures, set 1 = material]
  4. blit draw_image → swapchain
  5. present
```

### SceneData: Zig ↔ Shader field mapping

| Zig field (`command.zig SceneData`) | Shader field (`SceneData` in `scene.slang`) | Size |
|---|---|---|
| `view: zm.Mat` | `float4x4 view` | 64 bytes |
| `proj: zm.Mat` | `float4x4 proj` | 64 bytes |
| `view_proj: zm.Mat` | `float4x4 viewproj` | 64 bytes |
| `ambient_color: Color` | `float4 ambientColor` | 16 bytes |
| `sunlight_direction: @Vector(4, f32)` | `float4 sunlightDirection` | 16 bytes |
| `sunlight_color: Color` | `float4 sunlightColor` | 16 bytes |
| `time: f32` | `float4 time` | ⚠ Mismatch: Zig = 4 bytes, shader = 16 bytes |

> **Known mismatch**: `time` in `command.zig SceneData` is `f32` (4 bytes) but the shader declares `float4 time` (16 bytes). The struct is undersized by 12 bytes. Fix: change Zig to `time: @Vector(4, f32)` and only set index 0.

### GlobalDescriptor set layout (Vulkan)

| Field | Descriptor set | Binding | Type | Used by |
|---|---|---|---|---|
| `draw_image_descriptor` | set 0 | 0 | storage image | compute (sky) pass |
| `scene_descriptor_layout` | set 0 | 0 | uniform buffer (SceneData) | `_2d_bis` pass |
| `vk_2d_descriptor_set` | set 0 | 0+1 | combined_image_sampler × 2 | `_2d` pass (atlas + checker) |
| `vk_mesh_descriptor_set_layout` | set 0 | 0 = UBO, 1 = sampler[] | uniform_buffer + combined_image_sampler (variable, bindless) | `mesh` pass — **DISABLED** |
| `vk_material_descriptor_set_layout` | set 1 | 0 | uniform buffer (GLTFMaterialData) | `mesh` pass — **DISABLED** |

---

## Known issues

### 3D mesh rendering is disabled

Three interlocked pieces are commented out in `renderer/vulkan/engine.zig`:

1. **`createMeshPipeline()` not called** (line 428): `// try self.createMeshPipeline();`
2. **Mesh descriptor set not initialized** (lines 211–236 in `GlobalDescriptor.setup()`): the entire `// { // Mesh ... }` block that sets up `vk_mesh_descriptor_set_layout` and `vk_mesh_descriptor_set` is disabled.
3. **`draw_mesh()` not called** (line 543): `// self.draw_mesh(cmdbuf);`

Additionally, even if uncommented, `draw_mesh()` has a **descriptor/pipeline layout mismatch**: `createMeshPipeline()` currently declares only `vk_material_descriptor_set_layout` at set 0, but `draw_mesh()` binds `vk_mesh_descriptor_set` at set 0 and `vk_material_descriptor_set` at set 1.

And `draw_mesh()` **hardcodes `self.meshes.items[2]`** — assumes the loaded GLB contains at least 3 meshes at a fixed index.

See `docs/plans/mesh-rendering.md` for the step-by-step fix.
