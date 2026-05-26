# Analysis: Vulkan Blending

**Source:** https://vkguide.dev/docs/new_chapter_3/blending/

---

## What blending is

Blending is a fixed-function GPU stage that combines a fragment's output color with the existing value already in the render target. It runs after the fragment shader, in hardware, and is configured entirely through pipeline state — not through shaders.

This is what makes transparency and many graphical effects possible.

---

## The general formula

```
outColor = srcColor * srcColorBlendFactor <op> dstColor * dstColorBlendFactor
```

| Term | Meaning |
|---|---|
| `srcColor` | Color produced by the current fragment shader |
| `dstColor` | Color already in the render target (framebuffer) |
| `srcColorBlendFactor` | Multiplier applied to the fragment color |
| `dstColorBlendFactor` | Multiplier applied to the existing framebuffer color |
| `<op>` | The blend operation (typically `VK_BLEND_OP_ADD`) |

The same structure applies separately to the alpha channel via `srcAlphaBlendFactor` / `dstAlphaBlendFactor` / `alphaBlendOp`.

---

## The two standard modes

### Additive blending

```
srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA
dstColorBlendFactor = VK_BLEND_FACTOR_ONE
colorBlendOp        = VK_BLEND_OP_ADD
srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE
dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO
```

**Expanded result:**
```
outColor.rgb = srcColor.rgb * srcColor.a + dstColor.rgb * 1.0
```

The destination is never dimmed — both src and dst contribute fully. Overlapping transparent objects accumulate brightness. Used for fire, particles, glows, lasers.

---

### Alpha blending

```
srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA
dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
colorBlendOp        = VK_BLEND_OP_ADD
srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE
dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO
```

**Expanded result:**
```
outColor.rgb = srcColor.rgb * srcColor.a + dstColor.rgb * (1.0 - srcColor.a)
```

This is a lerp between src and dst driven by alpha. When `srcColor.a = 1.0` the result is fully opaque; when `srcColor.a = 0.0` the destination shows through completely. Used for glass, sprites, UI.

---

## Key difference between the two

| | Additive | Alpha |
|---|---|---|
| Destination factor | `ONE` (dst stays at full brightness) | `ONE_MINUS_SRC_ALPHA` (dst is dimmed) |
| Effect of stacking | Gets brighter | Stays bounded |
| Use case | Emissive / glow effects | Standard transparency |

---

## Implementation pattern

Both modes are exposed as builder functions on `PipelineBuilder` and configure the `VkPipelineColorBlendAttachmentState` struct:

- `colorWriteMask` is set to all four components (R, G, B, A)
- `blendEnable` is set to `VK_TRUE`
- The six blend factor / op fields are set as above

When blending is disabled (`blendEnable = VK_FALSE`), the fragment color is written directly to the render target with no compositing.

---

## Blend operators

`VK_BLEND_OP_ADD` is the baseline operator and the only one guaranteed without extensions. Advanced operators (min, max, multiply, screen, etc.) exist under `VK_EXT_blend_operation_advanced` but require explicit hardware support.

---

## Draw order dependency

Alpha blending is order-dependent. Because the dst color is read before writing, drawing back-to-front (painter's algorithm) gives correct results. Drawing front-to-back with alpha blending produces wrong compositing.

Additive blending is commutative — order does not matter since addition is symmetric.

---

## Relation to depth testing

Blending and depth testing are independent stages. A common setup for transparent geometry:

- Depth **test** enabled (transparent objects are occluded by opaque ones)
- Depth **write** disabled (transparent objects do not block each other in the depth buffer)

This requires opaque geometry to be drawn first in a separate pass.