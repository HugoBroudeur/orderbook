import include.scene;

// UI vertex, pulled via buffer-device-address. Field layout MUST match the
// Zig `UIVertex` extern struct (engine/data.zig): pos@0, uv@8, col@16 (float4,
// 16-aligned), tex_id@32, stride 48.
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
  float2 screen_size; // window size in pixels
  float2 _pad;
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

  // Pixel space (origin top-left) -> NDC. Vulkan NDC has +Y down, matching
  // top-left pixel origin, so no Y flip needed.
  float2 ndc = (input.Position / pc.screen_size) * 2.0 - 1.0;
  output.Position = float4(ndc.x, ndc.y, 0.0, 1.0);

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
