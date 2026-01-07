struct VertexUniformData {
  float2 Scale;
  float2 Translate;
};

struct VS_Input {
  float2 Position : POSITION;
  float2 TexCoord : TEXCOORD1;
  float4 Color : COLOR0;
};

struct PS_Input {
  float4 Position : SV_Position;
  float4 Color : COLOR0;
  float2 TexCoord : TEXCOORD0;
};

Texture2D<float4> Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

// This defines slot 0, space1 for the vertex stage
ConstantBuffer<VertexUniformData> vu : register(b0, space1);

[shader("vertex")]
PS_Input vertex(VS_Input input) {
  PS_Input output;
  output.TexCoord = input.TexCoord;
  output.Color = input.Color;
  output.Position.xy = input.Position * vu.Scale + vu.Translate;
  output.Position.zw = float2(0,  1);
  return output;
}

// Actual frament shader, using array for layered textured (atlas)
[shader("fragment")]
float4 fragment(PS_Input input) : SV_Target0 {
  // return input.Color * Texture.Sample(Sampler, input.TexCoord);
  return input.Color;
}
