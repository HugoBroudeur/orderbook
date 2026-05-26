---
name: gltf
description: Complete reference for the GLTF 2.0 / GLB binary format and the zgltf Zig library used in this codebase. Use when the user asks anything about GLTF, GLB, mesh loading, accessors, buffer views, vertex attributes, or when investigating bugs in asset_loader.zig or any code that calls zgltf. Always read this skill before answering GLTF questions or touching mesh loading code.
---

# GLTF Reference

See [REFERENCE.md](REFERENCE.md) for the full spec and library details.

## Quick orientation

GLTF separates **description** (JSON) from **data** (binary buffers):

```
Mesh → Primitive → Attribute (POSITION, NORMAL…)
                          ↓
                      Accessor  (type, count, componentType, byteOffset)
                          ↓
                     BufferView (byteOffset into buffer, byteLength, optional byteStride)
                          ↓
                       Buffer   (the raw bytes — in GLB this is the BIN chunk)
```

## Must-read before touching mesh loading

1. **Accessor byte offsets are from the start of `glb_binary`**, not from the accessor itself. The real start offset = `accessor.byte_offset + buffer_view.byte_offset`.

2. **zgltf iterator divides by `@sizeOf(T)`**. Offset stored internally as element index, not bytes:
   ```zig
   offset = (accessor.byte_offset + buffer_view.byte_offset) / @sizeOf(T)
   // For f32 (4 bytes): byte_offset 70088 → element offset 17522
   ```

3. **`glb_binary` is a slice into the file buffer** — it does NOT copy. Free the file buffer and you get garbage. `AssetLoader.file_buffers` holds ownership.

4. **Positions ≠ normals diagnostic**: If all vertex positions have `|mag| ≈ 1.0` and the first triangle's three vertices share identical positions, you are reading normals as positions. Verify with:
   ```python
   # Quick check: binary[bufferView[N].byteOffset] → first 12 bytes of that accessor
   ```

5. **Attribute parse order** (from zgltf `parseGltfJson`): position → normal → tangent → texcoords → joints → weights. This order is fixed regardless of the order in the GLTF file.

6. **Index component type**: GLTF indices are `unsigned_short` (u16) by default. Pass `u16` to the iterator, not `u32`. Mismatch panics at runtime.

7. **Single-parse rule**: `Gltf` uses an arena allocator. Calling `parse()` twice on the same instance appends to the arena without freeing old data — `data` fields are overwritten but old allocations leak. One `Gltf` instance per file (or call `deinit` + `init` between files).

## Common diagnostic snippet

```zig
// Print before iterator to confirm you are reading the right location
const acc = data.accessors[idx];
const bv = self.zgltf.data.buffer_views[acc.buffer_view.?];
std.debug.print("acc[{}] bufView={} bv.byte_offset={} acc.byte_offset={} → elem_offset={}\n", .{
    idx, acc.buffer_view.?, bv.byte_offset, acc.byte_offset,
    (bv.byte_offset + acc.byte_offset) / @sizeOf(f32),
});
```
