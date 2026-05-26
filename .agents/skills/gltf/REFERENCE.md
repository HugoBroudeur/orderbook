# GLTF 2.0 Reference — Full Spec + zgltf

## GLB binary file layout

```
Bytes 0–11   : GLB header
  u32 magic    = 0x46546C67 ('glTF')
  u32 version  = 2
  u32 length   (total file size)

Bytes 12–19  : JSON chunk header
  u32 chunkLength
  u32 chunkType = 0x4E4F534A ('JSON')

Bytes 20 .. 20+chunkLength-1 : JSON data (UTF-8)

Bytes 20+chunkLength .. 20+chunkLength+7 : BIN chunk header
  u32 chunkLength
  u32 chunkType = 0x004E4942 ('BIN\0')

Bytes 20+chunkLength+8 .. end : BIN chunk data
  ← this is what zgltf stores in Gltf.glb_binary
  ← ALL buffer view byte_offsets are relative to THIS start
```

## Object model

### Buffer
Raw bytes. In GLB there is always exactly one buffer; its data IS `glb_binary`. In .gltf files the buffer is an external `.bin` file referenced by URI.

### BufferView
A window into a buffer.
```
byte_offset  — offset from start of buffer (glb_binary[byte_offset])
byte_length  — length of this window
byte_stride  — if non-null, data is interleaved; stride in bytes between elements
               if null, data is tightly packed
target       — hint: array_buffer (34962) or element_array_buffer (34963)
```

### Accessor
A typed view of a BufferView.
```
buffer_view     — index into buffer_views[]
byte_offset     — additional byte offset WITHIN the buffer_view (usually 0)
component_type  — scalar base type (see ComponentType enum)
type            — element shape (scalar/vec2/vec3/vec4/mat*)
count           — number of elements
normalized      — integer → float normalization flag
```

The actual data byte address:
```
data_start = glb_binary.ptr + buffer_view.byte_offset + accessor.byte_offset
```

### Mesh / Primitive / Attribute
```
Mesh
  name
  primitives[]
    mode       — triangles (4) by default
    indices    — accessor index for index buffer (u16 or u32 SCALAR)
    material   — material index
    attributes — []Attribute (tagged union in zgltf)
      .position → accessor index  (VEC3 float)
      .normal   → accessor index  (VEC3 float, unit vectors)
      .tangent  → accessor index  (VEC4 float, w=±1 handedness)
      .texcoord → accessor index  (VEC2 float or u8/u16 normalized)
      .color    → accessor index  (VEC3/VEC4 float or u8/u16 normalized)
      .joints   → accessor index  (VEC4 u8/u16)
      .weights  → accessor index  (VEC4 float or u8/u16 normalized)
```

## ComponentType → Zig type mapping

| GLTF componentType | value | Zig type |
|---|---|---|
| BYTE | 5120 | i8 |
| UNSIGNED_BYTE | 5121 | u8 |
| SHORT | 5122 | i16 |
| UNSIGNED_SHORT | 5123 | u16 |
| UNSIGNED_INT | 5125 | u32 |
| FLOAT | 5126 | f32 |

## AccessorType component counts

| type | componentCount |
|---|---|
| SCALAR | 1 |
| VEC2 | 2 |
| VEC3 | 3 |
| VEC4 | 4 |
| MAT2 | 4 |
| MAT3 | 9 |
| MAT4 | 16 |

---

## zgltf API

### Init / deinit
```zig
var gltf = Gltf.init(allocator);   // allocates an ArenaAllocator internally
defer gltf.deinit();               // frees the arena
```

### Parsing
```zig
// Detects GLB vs. GLTF automatically from the magic number
try gltf.parse(file_buffer);
// After parse(), gltf.data contains all parsed objects
// For GLB: gltf.glb_binary is set (slice INTO file_buffer)
// For GLTF: gltf.glb_binary is null; pass external .bin as binary to iterator
```

**Critical**: `parse()` uses an arena — calling it twice on the same Gltf instance does NOT reset state. Old allocations remain in the arena. Always use a fresh `Gltf.init` or call `deinit` + `init` between files.

### Gltf.Data fields (post-parse)
```zig
gltf.data.meshes        []Mesh
gltf.data.accessors     []Accessor
gltf.data.buffer_views  []BufferView
gltf.data.buffers       []Buffer
gltf.data.materials     []Material
gltf.data.nodes         []Node
gltf.data.textures      []Texture
gltf.data.images        []Image
gltf.data.animations    []Animation
gltf.data.scenes        []Scene
gltf.data.lights        []Light     (KHR_lights_punctual)
```

### Accessor.iterator
```zig
pub fn iterator(
    accessor: Accessor,
    comptime T: type,       // must match accessor.component_type exactly
    gltf: *const Gltf,      // used to resolve buffer_views
    binary: []align(4) const u8,  // glb_binary (or external .bin)
) AccessorIterator(T)
```

**Offset arithmetic (internal)**:
```zig
offset = (accessor.byte_offset + buffer_view.byte_offset) / @sizeOf(T)
stride = if (buffer_view.byte_stride) |s| s / @sizeOf(T) else datum_count
// next() returns: binary_as_T_slice[offset + current*stride ..][0..datum_count]
```

**Return value of `next()`**: `?[]const T`
- For VEC3 float: returns a 3-element slice `[x, y, z]` per call
- For SCALAR u16: returns a 1-element slice `[index]` per call
- Returns `null` when `current >= accessor.count`

**Type mismatch**: panics with `"Mismatch between gltf component '{}' and given type '{}'."` — no error return.

**Example — reading positions**:
```zig
const accessor = data.accessors[position_accessor_idx];
var it = accessor.iterator(f32, &gltf, gltf.glb_binary.?);
while (it.next()) |v| {
    // v[0]=x, v[1]=y, v[2]=z
}
```

**Example — reading indices (u16)**:
```zig
const accessor = data.accessors[primitive.indices.?];
var it = accessor.iterator(u16, &gltf, gltf.glb_binary.?);
while (it.next()) |i| {
    const index: u16 = i[0];
}
```

### getDataFromBufferView (alternative)
Allocates and returns a flat `[]T` with all elements:
```zig
const positions = try gltf.getDataFromBufferView(f32, allocator, accessor, gltf.glb_binary.?);
defer allocator.free(positions);
// positions = [x0,y0,z0, x1,y1,z1, ...]
```

---

## Memory ownership rules

| Resource | Owner | Lifetime required |
|---|---|---|
| `glb_binary` | caller (file buffer) | as long as any data read via iterator is in use |
| `gltf.data.*` slices | gltf arena | until `gltf.deinit()` |
| strings (mesh.name etc.) | gltf arena | until `gltf.deinit()` |

**In this codebase**: `AssetLoader.file_buffers` holds the file buffers. `AssetLoader.zgltf` holds the Gltf instance. Both live for the same lifetime, so the constraint is satisfied.

---

## Known pitfalls in this codebase

### Normals read as positions
Symptom: all vertex positions have `|mag| ≈ 1.0`; all vertices of the same face share an identical "position".

Cause: the loop variable `idx` in `.position => |idx|` comes from the Attribute enum payload — if the enum value is actually `.normal { idx }` you'll get a normal accessor index. Check the actual tag before accessing.

Diagnostic: add this before the iterator call:
```zig
const bv = self.zgltf.data.buffer_views[accessor.buffer_view.?];
std.debug.print("acc bv_offset={} → elem_offset={}\n", .{
    bv.byte_offset, (bv.byte_offset + accessor.byte_offset) / @sizeOf(f32),
});
```
Then compare the printed element_offset × 4 against the expected `bufferView.byteOffset` from the JSON.

### Stale mesh.spv after scene.slang change
The build system only checks `mesh.slang` timestamp vs `mesh.spv`. It does NOT check `include/scene.slang`. After modifying any included file, `touch src/shaders/mesh.slang` to force recompilation.

### Y-flip only on proj, not on view_proj
`scene_manager.zig` applies `proj[1][1] *= -1` to `proj` but `view_proj` is obtained from `camera.getViewProjMatrix()` which uses the unflipped projection. The GPU shader reads `sceneData.viewproj` so it uses the un-flipped version. This is intentional — the flip is handled separately.

### SceneData.time layout mismatch
GPU shader declares `float4 time` (16 bytes). CPU sends `f32 time` (4 bytes). The last 12 bytes of the time field in the UBO are garbage. This doesn't affect `viewproj` (earlier in the struct) but will corrupt anything after `time`.

---

## Inspecting a GLB file

Use `docs/scripts/inspect_glb.py` — a full CLI tool for verifying byte offsets before touching the Zig loader:

```sh
# Summary: all meshes, buffer views, accessors with computed elem_off
python3 docs/scripts/inspect_glb.py file.glb

# Dump first 6 elements of accessor N as floats/u16s
python3 docs/scripts/inspect_glb.py file.glb --accessor N

# Dump N vec3s from buffer view index
python3 docs/scripts/inspect_glb.py file.glb --bufview N --n 8

# Hex + float dump at a specific binary byte offset
python3 docs/scripts/inspect_glb.py file.glb --bytes 70088 --count 24
```

The `elem_off` column matches what the Zig iterator computes:
```
elem_off = (accessor.byte_offset + bufview.byte_offset) / sizeof(T)
```
