## Librairies

### C librairies (must be installed on the machine)

SDL3
SDL3_ttf

## Prerequisite

On Open Suse

```bash
sudo zypper install SDL3-devel SDL3_ttf-devel SDL3_image-devel
sudo zypper install vulkan-tools vulkan-validationlayer
sudo zypper install slangc
```

For Fish
Export the Vulkan validation layer for debugging
```bash
# In ~/.config/fish/config.fish
set -gx VK_LAYER_PATH "/usr/share/vulkan/explicit_layer.d"
```

## Architecture (AI based but good ideas in there)
Good question — this is *architecture*, not syntax, and getting this wrong hurts later. I’ll answer this **as if you’re building a real engine**, not a demo.

I’ll give you:

1. **Mental model**
2. **Clear responsibilities**
3. **Concrete module layout**
4. **Data flow per frame**
5. **Common traps (what *not* to do)**

No fluff.

---

## 1. Mental model (this is the most important part)

You want **strict direction of dependencies**:

```
Game code
   ↓
Scene / ECS
   ↓
Render Queue (commands, data-only)
   ↓
Batcher (groups & sorts)
   ↓
Renderer (API-specific: SDL3/GPU/Vulkan/etc)
   ↓
GPU
```

> ❌ Renderer should NEVER know about ECS
> ❌ ECS should NEVER know about GPU
> ❌ Game logic should NEVER issue draw calls directly

Everything talks **downward**, never sideways.

---

## 2. Responsibilities (non-negotiable)

### ECS

**What it does**

* Owns entities & components
* Pure data + systems
* Knows *what exists*, not *how it’s drawn*

**What it does NOT do**

* No GPU handles
* No pipelines
* No textures

Example components:

```zig
Transform
Sprite
Mesh
Camera
Visibility
```

---

### Scene Manager

**What it does**

* Owns which ECS world(s) are active
* Handles loading/unloading
* High-level transitions

Think:

```zig
MainMenuScene
GameScene
EditorScene
```

> Scene manager ≠ ECS
> Scene manager orchestrates ECS worlds

---

### Render Queue (Draw Command Queue)

This is the **critical decoupling layer**.

**What it is**

* A flat array of **draw commands**
* POD / data-only
* No logic

Example:

```zig
const DrawCmd = struct {
    pipeline_id: PipelineId,
    mesh_id: MeshId,
    material_id: MaterialId,
    transform: Mat4,
    sort_key: u64,
};
```

**Who writes to it**

* Render systems (ECS systems)

**Who reads it**

* Batcher

---

### Batcher

**What it does**

* Sorts draw commands
* Groups compatible ones
* Produces *renderable batches*

Example responsibilities:

* Sort by pipeline → material → mesh
* Merge sprites into one vertex buffer
* Decide when to break batches

**What it does NOT do**

* No ECS
* No gameplay logic
* No GPU API calls

Think of it as:

> “CPU-side render optimizer”

---

### Renderer

**What it does**

* Owns GPU resources
* Knows about:

  * Pipelines
  * Buffers
  * Textures
  * Render passes
* Executes batches

**What it does NOT do**

* No scene logic
* No entity iteration
* No sorting

Renderer should be **dumb and deterministic**.

---

## 3. Concrete module layout (practical)

Here’s a layout that scales:

```
src/
├── core/
│   ├── math/
│   ├── memory/
│   └── platform/
│
├── ecs/
│   ├── world.zig
│   ├── entity.zig
│   ├── component.zig
│   └── systems/
│
├── scene/
│   ├── scene.zig
│   ├── scene_manager.zig
│   └── scenes/
│
├── render/
│   ├── render_queue.zig
│   ├── batcher.zig
│   ├── renderer.zig
│   ├── pipeline.zig
│   ├── mesh.zig
│   ├── material.zig
│   └── gpu/
│       └── sdl3_gpu.zig
│
├── assets/
│   ├── loader.zig
│   └── cache.zig
│
└── game/
    ├── main.zig
    └── systems/
```

---

## 4. Frame flow (step by step)

This is **exactly** what happens every frame:

```text
1. Input
2. Game logic systems
3. Scene update
4. Render systems:
     - Iterate ECS
     - Push DrawCmd into RenderQueue
5. Batcher:
     - Sort RenderQueue
     - Build Batches
6. Renderer:
     - Begin frame
     - Execute batches
     - End frame
```

In code terms:

```zig
scene.update(dt);

render_queue.clear();
render_systems.build(render_queue);

batcher.build(render_queue, batches);

renderer.render(batches);
```

---

## 5. How ECS connects to rendering (example)

A **render system**:

```zig
fn spriteRenderSystem(world: *World, rq: *RenderQueue) void {
    var it = world.query(.{ Transform, Sprite });
    while (it.next()) |e| {
        rq.push(.{
            .pipeline_id = sprite.pipeline,
            .mesh_id = sprite.mesh,
            .material_id = sprite.material,
            .transform = transform.matrix(),
            .sort_key = makeSortKey(sprite),
        });
    }
}
```

Notice:

* No GPU calls
* No SDL
* No batching logic

---

## 6. Sorting key (important detail)

Use a **64-bit sort key**:

```
[ pipeline | material | depth | mesh ]
```

Example:

```zig
fn makeSortKey(p: PipelineId, m: MaterialId, depth: u16) u64 {
    return (@as(u64, p) << 48) |
           (@as(u64, m) << 32) |
           (@as(u64, depth) << 16);
}
```

This makes batching trivial and fast.

---

## 7. Common mistakes (avoid these)

❌ Renderer iterates ECS
❌ ECS stores GPU pointers
❌ Scene owns GPU resources
❌ Batcher calls GPU
❌ Game logic calls draw()

If any of those happen, your architecture will rot.

---

## 8. Minimal version (if you want to start small)

If this feels like “too much”:

* Skip scene manager (one scene)
* Skip ECS (just arrays)
* Keep:

  * RenderQueue
  * Batcher
  * Renderer

But **do not skip the render queue**. That’s the keystone.

---

## Bottom line

If you remember one sentence:

> **ECS describes *what* should be drawn.
> Render queue records *intent*.
> Batcher optimizes it.
> Renderer executes it.**

If you want, next we can:

* Design a **sprite batcher**
* Design a **2D renderer API**
* Or map this exactly onto **SDL3 GPU + Zig**

