# Vulkan Guide — Resizing Window (Chapter 3)

**Date:** 2026-05-25
**Source:** https://vkguide.dev/docs/new_chapter_3/resizing_window/
**Audience:** Broad-strokes understanding of what the page teaches.

**Analysis rules used:** Page-faithful summary; external context only in section D.

---

## A. Page summary

### A.1. Why this page exists

Vulkan does not resize automatically. When the window changes size, "the swapchain becomes invalid, and the vulkan operations with the swapchain like `vkAcquireNextImageKHR` and `vkQueuePresentKHR` can fail with a `VK_ERROR_OUT_OF_DATE_KHR` error." The page implements the manual plumbing required to handle this.

### A.2. Core idea(s)

Rather than recreating the draw image and depth image on every resize, the page creates them once at startup with a **preset size** and then either:
- renders into **a section of the image** when the window is smaller, or
- **scales it up** when the window is bigger.

The page's stated reason: "we will not be reallocating the draw image. Right now we only have one draw image and depth image, but on a more developed engine it could be significantly more, and re-creating all that can be a considerable hassle."

A secondary benefit the page explicitly calls out: "This can also be used to perform dynamic resolution, which is a useful way of scaling performance, and can be handy for debugging."

`VkCmdBlit` is named as the mechanism that performs this scaling (it supports scaling operations).

### A.3. Key terms (page definitions)

| Term | Page definition |
|------|----------------|
| `VK_ERROR_OUT_OF_DATE_KHR` | Error returned by `vkAcquireNextImageKHR` / `vkQueuePresentKHR` when the swapchain is no longer valid after a resize |
| `resize_requested` | Boolean flag set when the above error is detected; used to defer the actual swapchain recreation |
| `_drawExtent` | `VkExtent2D` controlling how much of the draw image is actually rendered into each frame |
| `renderScale` | `float` multiplier applied to `_drawExtent` to support dynamic resolution (0.3–1.0 in the ImGui control) |

### A.4. Main mechanics / APIs the page introduces

**Catching the out-of-date error in `vkAcquireNextImageKHR`:**
```cpp
VkResult e = vkAcquireNextImageKHR(_device, _swapchain, 1000000000,
    get_current_frame()._swapchainSemaphore, nullptr, &swapchainImageIndex);
if (e == VK_ERROR_OUT_OF_DATE_KHR) {
    resize_requested = true;
    return;
}
```

**Catching it in `vkQueuePresentKHR`:**
```cpp
VkResult presentResult = vkQueuePresentKHR(_graphicsQueue, &presentInfo);
if (presentResult == VK_ERROR_OUT_OF_DATE_KHR) {
    resize_requested = true;
}
```

**`resize_swapchain()` function:**
```cpp
void VulkanEngine::resize_swapchain()
{
    vkDeviceWaitIdle(_device);

    destroy_swapchain();

    int w, h;
    SDL_GetWindowSize(_window, &w, &h);
    _windowExtent.width = w;
    _windowExtent.height = h;

    create_swapchain(_windowExtent.width, _windowExtent.height);

    resize_requested = false;
}
```

**Draw extent calculation (clamped + scaled):**
```cpp
_drawExtent.height = std::min(_swapchainExtent.height, _drawImage.imageExtent.height) * renderScale;
_drawExtent.width  = std::min(_swapchainExtent.width,  _drawImage.imageExtent.width)  * renderScale;
```
The `std::min` prevents rendering out of bounds when the window is larger than the preset draw image size. `renderScale` then sub-scales for dynamic resolution.

**ImGui dynamic resolution slider:**
```cpp
if (ImGui::Begin("background")) {
    ImGui::SliderFloat("Render Scale", &renderScale, 0.3f, 1.f);
    // other code
}
```

The page also notes: "The ImGui UI will still render into the swapchain image directly, so it will always render at native resolution."

### A.5. What the page has you do (hands-on steps)

1. Add `SDL_WINDOW_RESIZABLE` to the window creation flags in `VulkanEngine::init`:
   ```cpp
   SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);
   ```
2. In the `vkAcquireNextImageKHR` call: check for `VK_ERROR_OUT_OF_DATE_KHR`, set `resize_requested = true`, and `return` early.
3. In the `vkQueuePresentKHR` call: check for `VK_ERROR_OUT_OF_DATE_KHR` and set `resize_requested = true`.
4. At the top of the draw loop: check `resize_requested` and call `resize_swapchain()`.
5. Declare `VkExtent2D _drawExtent` and `float renderScale = 1.f` on the engine.
6. Replace any hardcoded draw extent with the `std::min(...) * renderScale` calculation each frame.
7. Add the `ImGui::SliderFloat("Render Scale", &renderScale, 0.3f, 1.f)` control.

### A.6. What comes next (if stated on the page)

"With this we have chapter 3 done, and can move forward to the next chapter." The page links directly to **Chapter 4: New Descriptor Abstractions**.

---

## B. What the page does *not* say

| Topic | On the page? |
|-------|-------------|
| `VK_SUBOPTIMAL_KHR` handling | No |
| Zero-size / minimized window handling | No |
| Fullscreen toggle handling | No |
| How `destroy_swapchain()` or `create_swapchain()` are implemented | No (treated as already existing) |
| How the draw image preset size is chosen | No |
| `VkCmdBlit` usage details / parameters | No (only named as enabling scaling) |
| Depth image reallocation specifics | No |
| Platform differences (X11, Wayland, Win32) | No |
| Premultiplied alpha or blending interaction with scaling | No |

---

## C. Takeaways (page-only)

The page closes out Chapter 3 by adding manual swapchain resize support. The key architectural choice is to **keep the draw image fixed** at startup and use `_drawExtent` — clamped with `std::min` and multiplied by `renderScale` — to control how much of it is used each frame. Resize events detected via `VK_ERROR_OUT_OF_DATE_KHR` are deferred through a `resize_requested` flag and handled at the top of the draw loop with `resize_swapchain()`. As a side effect, the same `renderScale` parameter doubles as a dynamic resolution knob exposed via an ImGui slider, while the UI itself continues rendering at native swapchain resolution.

---

## D. External notes (not on the page)

### D.1. `VK_SUBOPTIMAL_KHR`

*External note:* The Vulkan spec also defines `VK_SUBOPTIMAL_KHR` (swapchain still works but is no longer ideally matched to the surface). Many production engines treat it the same as `VK_ERROR_OUT_OF_DATE_KHR` and trigger a rebuild. The page does not mention it.

### D.2. Minimized / zero-size windows

*External note:* On some platforms a minimized window reports `width = 0, height = 0`. Passing zero extents to `create_swapchain` will cause a Vulkan validation error. A common guard is to loop until `SDL_GetWindowSize` returns non-zero before recreating. The page does not address this case.

### D.3. `vkDeviceWaitIdle` cost

*External note:* `vkDeviceWaitIdle` stalls the entire GPU pipeline. This is acceptable for infrequent resize events but would be expensive if called every frame. The page uses it correctly — only inside `resize_swapchain()` which is triggered by a flag, not every frame.
