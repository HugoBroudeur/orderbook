struct Input {
  float4 Position : TEXCOORD0;
  float2 TexCoord : TEXCOORD1;
};

struct Output {
  float2 TexCoord : TEXCOORD0;
  float4 Position : SV_Position;
};

Texture2DArray<float4> Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

[shader("vertex")]
Output vertex(Input input) {
  Output output;
  output.TexCoord = input.TexCoord;
  output.Position = input.Position;
  return output;
}

// Debug show UV color
// [shader("fragment")]
// float4 fragment(Output output) : SV_Target {
//   // UVs as color
//   return float4(output.TexCoord.x, output.TexCoord.y, 0.0, 1.0);
// }

// Debug show Pixel color
// [shader("fragment")]
// float4 fragment(Output output) : SV_Target {
//   return float4(0.5, 0.2, 0.7, 1.0); // Solid purple
// }

// Debug test Texture returns valid data
// [shader("fragment")]
// float4 fragment(Output input) : SV_Target {
//   float4 texColor = Texture.Sample(Sampler, input.TexCoord);
//
//   // If texture is black/empty, show magenta
//   if (texColor.r == 0.0 && texColor.g == 0.0 && texColor.b == 0.0) {
//     return float4(1.0, 0.0, 1.0, 1.0); // Magenta
//   }
//
//   return texColor;
// }

// Debug show magenta on black pixel
// [shader("fragment")]
// float4 fragment(Output input) : SV_Target {
//   float4 texColor = Texture.Sample(Sampler, float3(input.TexCoord, 0.0));
//
//   // Debug: show magenta if texture is black
//   if (length(texColor.rgb) < 0.01) {
//     return float4(1.0, 0.0, 1.0, 1.0); // Magenta = black texture
//   }
//   return texColor;
// }

// Actual frament shader, using array for layered textured (atlas)
[shader("fragment")]
float4 fragment(float2 TexCoord: TEXCOORD0) : SV_Target0 {
  uint arrayIndex = uint(int(TexCoord.y > 0.5f));
  return Texture.Sample(Sampler, float3(TexCoord, float(arrayIndex)));
}

