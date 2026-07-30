import include.scene;

// UI vertex, pulled via buffer-device-address. Slang uses NATURAL (scalar)
// layout for pointer types: pos@0, uv@8, col@16, tex_id@32, ArrayStride 36
// (not std430's 48). The Zig `UIVertex` extern struct (engine/data.zig) must
// match byte for byte — its layout test asserts size 36.
struct UIVertex {
  float2 Position;
  float2 TexCoord;
  float4 Color;
  uint TexId;
};

struct PS_Input {
  float4 Position : SV_Position;
  float4 Color : COLOR1;
  float2 TexCoord : TEXCOORD0;
  nointerpolation uint TexId : TEXCOORD1;
};

struct UIPushConstants {
  float4x4 mvp; // canvas-local pixel space -> clip space
  UIVertex *vertexBuffer;
}

[[vk::push_constant]]
ConstantBuffer<UIPushConstants> pc;

// Same global bindless set every other pipeline uses (set 0). We only need
// allTextures[] (binding 3) from it here.
public[[vk::binding(0, 0)]]
ParameterBlock<BindlessSceneParams> scene;

[shader("vertex")]
PS_Input vertex(uint vertexID: SV_VertexID) {
  UIVertex input = pc.vertexBuffer[vertexID];
  PS_Input output;

  // `mvp` is a zmath row-vector matrix read column-major by Slang, so mul(M, v)
  // == v * M (same convention as the 3D pipeline). Screen canvases pass a
  // pixel->NDC ortho (Vulkan +Y down matches the top-left pixel origin, no Y
  // flip); world canvases pass world_transform * view_proj. The quad lives in
  // the canvas's local z=0 plane.
  output.Position = mul(pc.mvp, float4(input.Position, 0.0, 1.0));

  output.Color = input.Color;
  output.TexCoord = input.TexCoord;
  output.TexId = input.TexId;
  return output;
}

[shader("fragment")]
float4 fragment(PS_Input input) : SV_Target {
  // allTextures[0] is the engine's white 1x1 fallback (resource manager seeds
  // it first), so a plain rectangle (TexId 0) samples white and is fully
  // determined by its vertex Color. Glyphs sample the font atlas; images
  // sample their own bindless slot.
  float4 texel = scene.allTextures[input.TexId].Sample(input.TexCoord);
  return input.Color * texel;
}
