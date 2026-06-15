# Plan: Window Resizing

**Source:** https://vkguide.dev/docs/new_chapter_3/resizing_window/
**Analysis:** docs/analysis/Vulkan Guide — Resizing Window (Chapter 3).md

---

## Current state

| Concern | Status |
|---------|--------|
| Window has `.resizable = true` | ✓ already in `WindowProps.flags` |
| `Swapchain.recreate()` exists | ✓ calls `deviceWaitIdle`, destroys + rebuilds |
| `FrameData.shouldReset()` triggers on window size change / suboptimal | ✓ |
| `OutOfDateKHR` caught and mapped to `.suboptimal` in `draw()` | ✓ |
| `draw_extent` concept (clamped + scaled active render region) | ✗ missing |
| Blit uses `window.toExtend2D()` as src size | ✗ broken — goes stale on resize, ignores draw_image bounds |
| Compute dispatch uses raw window size | ✗ should use draw_extent |
| Viewport/scissor updated only on swapchain recreate | ✗ not refreshed when draw_extent changes |
| `render_scale` dynamic resolution knob | ✗ missing |

The core problem: `fillCommandBuffers()` line 671 blits from `window.toExtend2D()` as
the source rectangle. After a resize the swapchain is correctly recreated, but the source
rect now refers to the new window size while `draw_image` is still sized at the initial
window dimensions — reading out of bounds. Adding a `draw_extent` that is always clamped
to `draw_image` dimensions fixes this and adds dynamic resolution for free.

---

## Architecture

Keep `draw_image` at its initial fixed size forever. Each frame compute `draw_extent` —
the region of `draw_image` that is actually rendered into:

```
draw_extent.width  = min(swapchain.extent.width,  draw_image.width)  * render_scale
draw_extent.height = min(swapchain.extent.height, draw_image.height) * render_scale
```

All render passes (mesh, compute background, viewport/scissor) target `draw_extent`.
The blit copies from `draw_extent` to the full swapchain extent, letting Vulkan scale
up or letterbox as needed. ImGui continues to render at native swapchain resolution
(it is rendered after the blit, into the swapchain image directly — deferred until
ImGui is wired into the Vulkan path).

---

## Steps

### Step 1 — Add fields to `Renderer` struct
**File:** `src/renderer/vulkan/engine.zig`

Add after `is_minimised`:
```zig
draw_extent: vk.Extent2D = .{ .width = 0, .height = 0 },
render_scale: f32 = 1.0,
```

### Step 2 — Compute `draw_extent` each frame in `draw()`
**File:** `src/renderer/vulkan/engine.zig`, function `draw()`

After the `shouldReset` block (whether or not recreation happened), add:
```zig
self.draw_extent = .{
    .width  = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.width,  self.draw_image.width)))  * self.render_scale),
    .height = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.height))) * self.render_scale),
};
// Keep viewport/scissor in sync so fillCommandBuffers always records correct values.
current_frame.viewport.width  = @floatFromInt(self.draw_extent.width);
current_frame.viewport.height = @floatFromInt(self.draw_extent.height);
current_frame.scissor.extent  = self.draw_extent;
```

This replaces the current pattern where viewport/scissor are only set inside
`FrameData.reset()` (which is only called when the swapchain is recreated).

### Step 3 — Fix the blit source rect
**File:** `src/renderer/vulkan/engine.zig`, function `fillCommandBuffers()`

Line ~671, change:
```zig
// before
Image.vkCopyImageToImage(self.ctx, cmdbuf, draw_image.vk_image, self.swapchain.currentImage(),
    self.ctx.window.toExtend2D(), self.swapchain.extent);

// after
Image.vkCopyImageToImage(self.ctx, cmdbuf, draw_image.vk_image, self.swapchain.currentImage(),
    self.draw_extent, self.swapchain.extent);
```

### Step 4 — Fix compute dispatch to use `draw_extent`
**File:** `src/renderer/vulkan/engine.zig`, function `draw_background()`

Change:
```zig
// before
const group_count_x: u32 = @intCast((self.ctx.window.getWidth())  / 16);
const group_count_y: u32 = @intCast((self.ctx.window.getHeight()) / 16);

// after
const group_count_x: u32 = (@max(self.draw_extent.width,  1) + 15) / 16;
const group_count_y: u32 = (@max(self.draw_extent.height, 1) + 15) / 16;
```

Note: adding the `+ 15` ceiling division so the last tile is always covered.
Also guards against a zero extent (minimised window) to avoid dispatching 0 groups
calling `cmdDispatch(0, _, _)`.

### Step 5 — (Deferred) ImGui render_scale slider

The guide calls for:
```
ImGui::SliderFloat("Render Scale", &renderScale, 0.3f, 1.f);
```

Skip until ImGui is wired into the Vulkan command recording path. When that lands,
add the slider in the ImGui window that already exists for background/scene controls.
The `render_scale` field added in Step 1 will be read automatically in Step 2's
`draw_extent` calculation once the slider writes to it.

---

## What does NOT change

- `draw_image` allocation (`createTextures`) — stays at initial window size, never reallocated.
- `Swapchain.recreate()` — already correct.
- The `OutOfDateKHR` catch in `draw()` — already correct.

---

## Bugs in `FrameData.shouldReset()` / `FrameData.reset()`

The plan originally said these were "kept as-is", but verification found three bugs that must be fixed as part of this work.

### Bug 1 — Command buffer leak in `reset()` (severity: medium)

**File:** `src/renderer/vulkan/engine.zig`, lines 103–112

`reset()` calls `createCommandBuffer()` which allocates a new `vk.CommandBuffer` into
`self.cmd_buf` without freeing the previous one. Every swapchain recreate (i.e. every
resize) leaks one command buffer per frame in flight. With `FRAME_OVERLAP = 2` and
enough resizes, the pool can be exhausted.

**Fix:** free the old command buffer before allocating a new one, or reset the command pool:

```zig
pub fn reset(self: *FrameData, ctx: *const GraphicsContext, extent: vk.Extent2D) !void {
    self.viewport.width  = @floatFromInt(extent.width);
    self.viewport.height = @floatFromInt(extent.height);
    self.scissor.extent  = extent;
    self.previous_frame_window_size = .{ .width = @intCast(ctx.window.getWidth()), .height = @intCast(ctx.window.getHeight()) };
    self.swapchain_state = .optimal;  // clear stale state (see Bug 3)

    // Free old buffer before allocating a new one.
    ctx.device.freeCommandBuffers(self.cmd_pool.vk_cmd_pool, 1, @ptrCast(&self.cmd_buf));
    try self.createCommandBuffer(ctx);
}
```

### Bug 2 — `errdefer` is ordered after `try` in `createCommandBuffer()` (severity: low)

**File:** `src/renderer/vulkan/engine.zig`, lines 85–92

```zig
pub fn createCommandBuffer(self: *FrameData, ctx: *const GraphicsContext) !void {
    try ctx.device.allocateCommandBuffers(..., @ptrCast(&self.cmd_buf));
    errdefer ctx.devive.freeCommandBuffers(...);  // ← never runs: placed AFTER the try
}
```

`errdefer` only covers code that executes after its declaration. Because it comes after
the `try`, if `allocateCommandBuffers` fails the `errdefer` is never registered and the
cleanup never runs. Also `ctx.devive` is a typo for `ctx.device` — if this path ever
executes it would panic. In practice `allocateCommandBuffers` rarely fails, so this is
silent. Fix by removing the dead `errdefer` (cleanup is now handled by the explicit
`freeCommandBuffers` call added in Bug 1's fix).

### Bug 3 — Double swapchain recreate with `FRAME_OVERLAP = 2` (severity: low)

**File:** `src/renderer/vulkan/engine.zig`, lines 54, 94–101, 109

`previous_frame_window_size` is stored per `FrameData` instance. After a resize:

1. Frame N (`frame_data[0]`) runs → `shouldReset()` true → recreate → `reset()` updates `frame_data[0].previous_frame_window_size`.
2. Frame N+1 (`frame_data[1]`) runs → `shouldReset()` true because `frame_data[1].previous_frame_window_size` still has the old size → **unnecessary second recreate**.

The second recreate is a spurious `vkDeviceWaitIdle` stall. Functionally it produces the
correct result (same dimensions passed to `recreate()`), but it hurts resize latency.

**Fix:** `reset()` must update both frames' `previous_frame_window_size` (or use a single
shared field on `Renderer`). Simplest approach — pass a pointer to a shared size field:

```zig
// In Renderer struct (alternative to per-frame tracking):
last_window_size: struct { width: u32, height: u32 } = .{ .width = 0, .height = 0 },
```

And in `shouldReset()`, compare against this shared field instead. Update it once in
`draw()` after `swapchain.recreate()` succeeds so both frames see the new value
immediately. Since `reset()` is per-frame, update it there and drop
`previous_frame_window_size` from `FrameData`.

---

## Revised "What does NOT change"

- `draw_image` allocation (`createTextures`) — stays at initial window size, never reallocated.
- `Swapchain.recreate()` — already correct.
- The `OutOfDateKHR` catch in `draw()` — already correct.

---

## Edge cases from the analysis doc

| Case | Handling |
|------|----------|
| `VK_SUBOPTIMAL_KHR` | Already mapped to `.suboptimal` → triggers recreate next frame |
| Minimised window (0×0) | `@max(..., 1)` in Step 4 prevents zero dispatch; `draw_extent` becomes 0×0 so blit copies nothing; present is skipped by existing `is_minimised` guard |
| Window larger than initial draw_image | `@min()` in Step 2 clamps so the blit never reads out of bounds |
| `vkDeviceWaitIdle` on resize | Already in `Swapchain.recreate()` — correct for infrequent resize |
| Resize while Bug 3 is present | Two recreates per resize event; functionally correct but doubles GPU stall |
