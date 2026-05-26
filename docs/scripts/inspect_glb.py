#!/usr/bin/env python3
"""
inspect_glb.py — GLB binary inspector for debugging mesh loading issues.

Usage:
    python3 docs/scripts/inspect_glb.py path/to/file.glb
    python3 docs/scripts/inspect_glb.py path/to/file.glb --accessor 3
    python3 docs/scripts/inspect_glb.py path/to/file.glb --bufview 2 --n 8
    python3 docs/scripts/inspect_glb.py path/to/file.glb --bytes 70088 --count 12

What it does:
  Default (no flags): print all meshes, buffer views, and accessors with their
  byte offsets and element offsets. Use this to verify that the Zig iterator
  will compute the right offset before running the engine.

  --accessor N: dump the first few elements of accessor N as floats or u16s.
  --bufview N:  dump the first --n vec3s from buffer view N.
  --bytes OFF:  hex + float dump starting at binary byte offset OFF.

Context:
  All buffer view byte_offsets are relative to the start of the BIN chunk data.
  The Zig iterator computes:
      elem_offset = (accessor.byte_offset + bufview.byte_offset) / sizeof(T)
  If elem_offset * 4 != bufview.byte_offset, something is wrong.
"""

import struct
import json
import argparse
import sys

COMPONENT_TYPE_NAMES = {
    5120: "i8", 5121: "u8", 5122: "i16",
    5123: "u16", 5125: "u32", 5126: "f32",
}
COMPONENT_TYPE_SIZES = {
    5120: 1, 5121: 1, 5122: 2,
    5123: 2, 5125: 4, 5126: 4,
}
ACCESSOR_TYPE_COUNTS = {
    "SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4,
    "MAT2": 4, "MAT3": 9, "MAT4": 16,
}


def parse_glb(path):
    with open(path, "rb") as f:
        data = f.read()

    magic, version, total_len = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, f"Not a GLB file (magic={magic:#010x})"
    assert version == 2, f"Unsupported GLB version {version}"

    json_chunk_len, json_chunk_type = struct.unpack_from("<II", data, 12)
    assert json_chunk_type == 0x4E4F534A, "Expected JSON chunk"
    gltf = json.loads(data[20:20 + json_chunk_len])

    bin_start = 12 + 8 + json_chunk_len
    bin_chunk_len, bin_chunk_type = struct.unpack_from("<II", data, bin_start)
    assert bin_chunk_type == 0x004E4942, "Expected BIN chunk"
    binary = data[bin_start + 8: bin_start + 8 + bin_chunk_len]

    return gltf, binary


def print_summary(gltf, binary):
    print(f"BIN chunk size: {len(binary)} bytes\n")

    print("=== MESHES ===")
    for mi, mesh in enumerate(gltf.get("meshes", [])):
        print(f"  mesh[{mi}] '{mesh.get('name', '')}'")
        for pi, prim in enumerate(mesh.get("primitives", [])):
            print(f"    primitive[{pi}]  indices={prim.get('indices', 'none')}")
            for attr, acc_idx in prim.get("attributes", {}).items():
                print(f"      {attr:12s} → accessor[{acc_idx}]")

    print("\n=== BUFFER VIEWS ===")
    for i, bv in enumerate(gltf.get("bufferViews", [])):
        off = bv.get("byteOffset", 0)
        ln  = bv.get("byteLength", 0)
        stride = bv.get("byteStride", "-")
        print(f"  bufView[{i:2d}]  offset={off:8d}  length={ln:8d}  stride={stride}")

    print("\n=== ACCESSORS ===")
    for i, acc in enumerate(gltf.get("accessors", [])):
        bv_idx   = acc.get("bufferView", None)
        acc_off  = acc.get("byteOffset", 0)
        ctype    = acc.get("componentType", 0)
        atype    = acc.get("type", "?")
        count    = acc.get("count", 0)
        csize    = COMPONENT_TYPE_SIZES.get(ctype, 0)
        cname    = COMPONENT_TYPE_NAMES.get(ctype, str(ctype))

        if bv_idx is not None:
            bv = gltf["bufferViews"][bv_idx]
            bv_off = bv.get("byteOffset", 0)
            byte_addr  = bv_off + acc_off
            elem_off   = byte_addr // csize if csize else "?"
            print(f"  acc[{i:2d}]  bufView={bv_idx}  "
                  f"bv_off={bv_off:8d} + acc_off={acc_off:5d} = byte={byte_addr:8d}  "
                  f"elem_off={elem_off}  "
                  f"type={atype}/{cname}  count={count}")
        else:
            print(f"  acc[{i:2d}]  no bufferView  type={atype}/{cname}  count={count}")


def dump_accessor(gltf, binary, acc_idx, n=6):
    acc    = gltf["accessors"][acc_idx]
    bv_idx = acc.get("bufferView")
    bv     = gltf["bufferViews"][bv_idx]
    ctype  = acc.get("componentType", 5126)
    atype  = acc.get("type", "SCALAR")
    count  = acc.get("count", 0)
    csize  = COMPONENT_TYPE_SIZES.get(ctype, 4)
    cname  = COMPONENT_TYPE_NAMES.get(ctype, str(ctype))
    ncomp  = ACCESSOR_TYPE_COUNTS.get(atype, 1)
    stride = bv.get("byteStride") or (ncomp * csize)
    base   = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)

    fmt_char = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}.get(ctype, "f")
    fmt = f"<{ncomp}{fmt_char}"

    print(f"accessor[{acc_idx}]  {atype}/{cname}  count={count}  base_byte={base}")
    for i in range(min(n, count)):
        off = base + i * stride
        vals = struct.unpack_from(fmt, binary, off)
        print(f"  [{i:4d}] {vals}")


def dump_bufview_vec3(gltf, binary, bv_idx, n=6):
    bv  = gltf["bufferViews"][bv_idx]
    off = bv.get("byteOffset", 0)
    ln  = bv.get("byteLength", 0)
    print(f"bufView[{bv_idx}]  byte_offset={off}  length={ln}")
    for i in range(n):
        byte_off = off + i * 12
        if byte_off + 12 > off + ln:
            break
        x, y, z = struct.unpack_from("<fff", binary, byte_off)
        print(f"  [{i:4d}] ({x:.5f}, {y:.5f}, {z:.5f})")


def dump_bytes(binary, offset, count=16):
    print(f"binary[{offset}:{offset+count}]")
    chunk = binary[offset:offset + count]
    hex_str  = " ".join(f"{b:02x}" for b in chunk)
    float_vals = []
    for i in range(0, len(chunk) - 3, 4):
        v, = struct.unpack_from("<f", chunk, i)
        float_vals.append(f"{v:.5f}")
    print(f"  hex:    {hex_str}")
    print(f"  floats: {float_vals}")


def main():
    parser = argparse.ArgumentParser(description="Inspect a GLB file for mesh debugging.")
    parser.add_argument("path", help="Path to .glb file")
    parser.add_argument("--accessor", type=int, default=None, metavar="N",
                        help="Dump first elements of accessor N")
    parser.add_argument("--bufview", type=int, default=None, metavar="N",
                        help="Dump first --n vec3s from buffer view N")
    parser.add_argument("--bytes", type=int, default=None, metavar="OFF",
                        help="Hex+float dump at binary byte offset OFF")
    parser.add_argument("--n", type=int, default=6,
                        help="Number of elements to print (default 6)")
    parser.add_argument("--count", type=int, default=16,
                        help="Byte count for --bytes (default 16)")
    args = parser.parse_args()

    gltf, binary = parse_glb(args.path)

    if args.accessor is not None:
        dump_accessor(gltf, binary, args.accessor, n=args.n)
    elif args.bufview is not None:
        dump_bufview_vec3(gltf, binary, args.bufview, n=args.n)
    elif args.bytes is not None:
        dump_bytes(binary, args.bytes, count=args.count)
    else:
        print_summary(gltf, binary)


if __name__ == "__main__":
    main()
