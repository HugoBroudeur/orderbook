# Debugging, Logging & Testing Guide

Practical reference for day-to-day development on this engine. Assumes familiarity with Zig basics.

---

## Logging

### Which logger to use

| Situation | Use |
|---|---|
| One-shot diagnostics during investigation | `std.debug.print(...)` |
| Startup / teardown events, errors that always matter | `std.log.info/err(...)` |
| Hot path (per-frame, per-vertex) | `LogManager` or `MaxLogs` — never raw `std.log` |

**Never leave raw `std.debug.print` in committed code.** It bypasses throttling and floods the terminal on the first frame.

### Marking debug blocks

Wrap any temporary diagnostic code in delimiter comments so it's easy to find and remove:

```zig
// ================== DEBUG ===============
std.debug.print("[Mesh] vertex[0] pos=({d:.4},{d:.4},{d:.4})\n",
    .{ v.pos[0], v.pos[1], v.pos[2] });
// ==================================
```

This makes `grep "DEBUG ===" src/` a reliable way to audit what's still in before committing.

### `std.log` levels

```zig
std.log.debug("verbose detail: {}", .{val});   // stripped in ReleaseFast/ReleaseSmall
std.log.info("[Module.fn] message", .{val});   // always emitted
std.log.warn("[Module.fn] degraded: {}", .{v});
std.log.err("[Module.fn] fatal: {}", .{err});
```

Convention in this codebase: prefix with `[TypeName.methodName]` so grepping the terminal output is fast.

### `LogManager` — per-session throttle

`src/game/log_manager.zig` wraps `std.log` with a global counter. After `max_logs` (default 100) calls it goes silent. Use it for anything called from the render loop:

```zig
const LogManager = @import("../game/log_manager.zig");

LogManager.info("[Renderer.draw] verts={}", .{count});
LogManager.err("[Renderer.draw] upload failed: {}", .{err});
```

### `MaxLogs(N)` — per-instance throttle

`src/core/log.zig` provides a comptime type that lets each subsystem have its own limit:

```zig
const Logger = @import("../../core/log.zig").MaxLogs(50);

Logger.info("buffer mapped at 0x{x}", .{ptr});
Logger.err("descriptor write failed", .{});
```

Good when you want module A to show 50 messages and module B to show 10, without them sharing a counter.

### Reading log output

The engine writes to stderr. Run with:

```sh
zig build run 2>&1 | tee /tmp/run.log
```

Then in a second terminal:

```sh
grep "ERROR\|err\|SELFTEST\|ITER" /tmp/run.log
```

Vulkan validation errors appear as `[Vulkan]` lines from the debug-utils callback in `src/core/graphics_context.zig`. They always print — no throttling.

---

## Debugging

### The SELFTEST pattern

After uploading mesh data, dump vertex 0 and the last vertex to confirm the GPU will see sensible data. Pattern used in `asset_loader.loadMeshes`:

```zig
// Right after the upload loop, before returning:
const first = vertices.items[0];
const last  = vertices.items[vertices.items.len - 1];
std.debug.print("[SELFTEST] first: pos=({d:.3},{d:.3},{d:.3}) col=({d:.2},{d:.2},{d:.2},{d:.2})\n",
    .{ first.pos[0], first.pos[1], first.pos[2],
       first.col[0], first.col[1], first.col[2], first.col[3] });
std.debug.print("[SELFTEST] last:  pos=({d:.3},{d:.3},{d:.3})\n",
    .{ last.pos[0], last.pos[1], last.pos[2] });
```

Diagnostic signals:

| What you see | Diagnosis |
|---|---|
| All positions have `|mag| ≈ 1.0` | Reading normal accessor as position |
| `0xAA` bytes / index value `43690` | Use-after-free (Zig debug allocator) |
| All positions `(0, 0, 0)` | Wrong accessor index or zero-init bug |
| Positions look right but mesh invisible | Pipeline, descriptor, or draw call issue |

### Before/after write diagnostics

When a write looks suspicious (or was confirmed to clobber adjacent memory), bracket it:

```zig
std.debug.print("BEFORE: pos=({d:.4},{d:.4},{d:.4})\n",
    .{ v.pos[0], v.pos[1], v.pos[2] });
v.normal = .{ nx, ny, nz };
std.debug.print("AFTER:  pos=({d:.4},{d:.4},{d:.4})\n",
    .{ v.pos[0], v.pos[1], v.pos[2] });
```

If `pos` changes after writing `normal`, you have a struct layout bug (wrong `packed struct` / `extern struct`, or SIMD alignment hazard — see the `Vertex` history in `src/renderer/data.zig`).

### Control meshes

`Renderer.selftest_mesh` (triangle) and `Renderer.cube_mesh` (unit cube, 6 face colors) are always rendered. If they appear and your mesh doesn't:
- The pipeline works.
- The fault is in your mesh's data path: accessor offsets, vertex upload, index upload, or draw call parameters.

If neither appears, suspect the pipeline or the descriptor set wiring.

### Inspecting a GLB file from Python

Before running the engine, confirm the accessor byte offsets are what you expect. Use `docs/scripts/inspect_glb.py`:

```sh
# Print all meshes, buffer views, and accessors with byte offsets
python3 docs/scripts/inspect_glb.py assets/meshes/suzanne.glb

# Dump the first 6 elements of accessor 3 as floats
python3 docs/scripts/inspect_glb.py assets/meshes/suzanne.glb --accessor 3

# Dump 8 vec3s from buffer view 2
python3 docs/scripts/inspect_glb.py assets/meshes/suzanne.glb --bufview 2 --n 8

# Hex + float dump at a specific binary byte offset (e.g. to verify positions start at 70088)
python3 docs/scripts/inspect_glb.py assets/meshes/suzanne.glb --bytes 70088 --count 24
```

The `elem_off` column in the accessor summary is exactly what the Zig iterator computes:
```
elem_off = (accessor.byte_offset + bufview.byte_offset) / sizeof(T)
```
If `elem_off * 4 != bufview.byte_offset`, something in the loader is misreading the source.

Use this when:
- The SELFTEST dump shows positions with `|mag| ≈ 1.0` (normals-as-positions).
- Positions are all-zero even though the accessor count is non-zero.
- You want to verify a specific vertex value before adding ITER-DBG prints to the engine.

### Vulkan validation layers

Always on — `VK_LAYER_KHRONOS_validation` is hardcoded in `graphics_context.zig`. No env var. Read **all** validation output before chasing a render bug; a missing barrier or wrong image layout will cascade into confusing visual results.

### Shader debugging

Shaders are Slang → SPIR-V (compiled by `tools/compile_shader.zig` on every `zig build`). To rule out shader issues quickly, switch the fragment shader to output a constant color or the raw vertex color:

```slang
// mesh.slang fragment — temporary debug
[shader("fragment")]
float4 fragment(Fragment input) : SV_Target {
    return float4(input.color, 1.0);   // solid vertex color, no texture
}
```

To force a shader recompile after editing:
```sh
touch src/shaders/*.slang && zig build
```

---

## Writing Tests

### Running tests

```sh
zig build test          # run all tests
zig build test 2>&1     # capture output (tests print to stderr)
```

Tests live alongside the source — no separate `tests/` directory. The build system picks them up automatically via `exe.root_module`.

### Test block anatomy

```zig
const std = @import("std");

test "Thing.method does X when Y" {
    const result = Thing.method(input);
    try std.testing.expectEqual(expected, result);
}
```

`try` propagates the test failure up; forgetting it silently swallows errors.

### `std.testing` assertions

| Assertion | Use |
|---|---|
| `expectEqual(expected, actual)` | Exact value equality |
| `expectApproxEqAbs(a, b, tolerance)` | Float comparison |
| `expectEqualSlices(T, a, b)` | Byte-for-byte slice equality |
| `expectError(err, expr)` | Confirm a specific error is returned |
| `expect(condition)` | Raw boolean — avoid; use the typed helpers |

### What to test in this engine

**Struct layout tests** — the most important tests here. Any struct shared between Zig and a GLSL/Slang shader must have its size and field offsets asserted. If the layout drifts, the GPU reads garbage and the error is silent. Pattern from `src/renderer/data.zig`:

```zig
test "Vertex layout matches mesh.slang expectation" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(Vertex));
    try std.testing.expectEqual(@as(usize,  0), @offsetOf(Vertex, "pos"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(Vertex, "uv_x"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Vertex, "normal"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(Vertex, "uv_y"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(Vertex, "col"));
}
```

Write one of these whenever you add or change a struct that touches a shader or a GPU buffer.

**Pure math** — `src/game/ecs/math/vec.zig` has examples. Any function that transforms data (projection matrix, AABB merge, accessor offset arithmetic) is worth a unit test because the inputs and expected outputs are known.

**Data structure invariants** — `src/data_structure.zig` has a skeleton. If a container (e.g. the orderbook) has invariants (sorted price levels, no duplicate IDs), test them with small fixed inputs.

### What not to test

- **GPU code** — Vulkan calls, buffer uploads, command recording. These require a live device and are exercised by running the engine. Use the control mesh / SELFTEST pattern instead.
- **Third-party library internals** — `zgltf`, `zmath`, `sdl3`. Trust them; test your usage of them.
- **Trivial getters** — if a function is a single field access with no logic, skip the test.

### Using `std.testing.allocator`

The testing allocator detects leaks and reports them as test failures. Use it for any test that allocates:

```zig
test "MyList appends without leaking" {
    const alloc = std.testing.allocator;
    var list = try MyList.init(alloc);
    defer list.deinit();

    try list.append(42);
    try std.testing.expectEqual(@as(usize, 1), list.len());
}
```

If you need thread safety:
```zig
var ts = std.heap.ThreadSafeAllocator{ .child_allocator = std.testing.allocator };
const alloc = ts.allocator();
```

---

## Quick reference: picking the right approach

| I want to… | Do this |
|---|---|
| See if a value is what I expect right now | `std.debug.print` + run |
| Confirm a struct matches the shader permanently | Layout test with `@sizeOf` / `@offsetOf` |
| Verify a GPU mesh rendered correctly | Control mesh + SELFTEST dump |
| Verify accessor byte offsets before running the engine | `python3 docs/scripts/inspect_glb.py file.glb` |
| Understand why the mesh is invisible | Validation layers → descriptor → draw params |
| Stop a hot path from spamming the terminal | `LogManager` or `MaxLogs(N)` |
| Assert pure logic is correct long-term | `test` block + `std.testing` |
