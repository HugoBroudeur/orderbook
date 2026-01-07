// struct PerModel {
//   uint64_t time;
//   // float4x4    modelTransform;
//   // float4x4    inverseTransposeModelTransform;
// };
// ParameterBlock<PerModel> gModelParams;

struct VertexUniformData {
  float4x4 proj_matrix;
  // float4 view_matrix;
};

struct FragmentUniformData {
  float time;
};

// Uniforms (using register bindings for set 1)
// cbuffer PositionUniform : register(b0, space1) { int3 u_position; };
// cbuffer ViewUniform : register(b1, space1) { float4x4 view_matrix; };
// cbuffer ProjUniform : register(b2, space1) { float4x4 proj_matrix; };

struct VS_Input {
  float4 Position : TEXCOORD0;
  float2 TexCoord : TEXCOORD1;
};

struct PS_Input {
  float2 TexCoord : TEXCOORD0;
  float4 Position : SV_Position;
};

Texture2DArray<float4> Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

// This defines slot 0, space3 for the fragment stage
ConstantBuffer<FragmentUniformData> fu : register(b0, space3);

// This defines slot 0, space1 for the vertex stage
ConstantBuffer<VertexUniformData> vu : register(b0, space1);

[shader("vertex")]
PS_Input vertex(VS_Input input) {
  PS_Input output;
  output.TexCoord = input.TexCoord;
  output.Position = mul(vu.proj_matrix, input.Position);
  return output;
}

// Actual frament shader, using array for layered textured (atlas)
[shader("fragment")]
float4 fragment(float2 TexCoord: TEXCOORD0) : SV_Target0 {
  uint arrayIndex = uint(int(TexCoord.y > 0.5f));
  return Texture.Sample(Sampler, float3(TexCoord, float(arrayIndex)));
  // float4 tex_col = Texture.Sample(Sampler, float3(TexCoord,
  // float(arrayIndex))); return float4(abs(cos(uniform.time * 0.000001)) *
  // tex_col.x,
  //               abs(cos(uniform.time * 0.000001 + 10)) * tex_col.y,
  //               abs(cos(uniform.time * 0.000001) + 20) * tex_col.z,
  //               tex_col.w);
}

// Debug show UV color
// [shader("fragment")]
// float4 fragment(PS_Input output) : SV_Target {
// UVs as color
// Animate color using sine wave
// float r = (abs(sin(uniform.time * 2.0)) + 1.0) * 0.5;
// float g = (abs(sin(uniform.time * 2.0 + 2.094)) + 1.0) * 0.5;
// float b = (abs(sin(uniform.time * 2.0 + 4.188)) + 1.0) * 0.5;

// Pulsing single color
// float pulse = (sin(uniform.time * 3.0) + 1.0) * 0.5;
// return float4(pulse, pulse * 0.5, pulse * 0.2, 1.0);

// Rainbow cycle
// float hue = fmod(u_time * 0.5, 1.0);
// (You'd need to convert HSV to RGB here)

// Position-based with time offset
// float wave = sin(input.position.x * 0.1 + u_time);
// return float4(wave, wave * 0.5, 1.0 - wave, 1.0);

// return float4(r, g, b, 1.0);
// return float4(abs(cos(output.TexCoord.x * gModelParams.time)),
// output.TexCoord.y, 0.0, 1.0);
// }

// Debug show Pixel color
// [shader("fragment")]
// float4 fragment(PS_Input output) : SV_Target {
//   return float4(abs(cos(uniform.time * 0.000001)), 0.2, 0.7,
//                 1.0); // Solid purple
//   // return float4(0.5, 0.2, 0.7, 1.0); // Solid purple
// }

// Debug test Texture returns valid data
// [shader("fragment")]
// float4 fragment(PS_Input input) : SV_Target {
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
// float4 fragment(PS_Input input) : SV_Target {
//   float4 texColor = Texture.Sample(Sampler, float3(input.TexCoord, 0.0));
//
//   // Debug: show magenta if texture is black
//   if (length(texColor.rgb) < 0.01) {
//     return float4(1.0, 0.0, 1.0, 1.0); // Magenta = black texture
//   }
//   return texColor;
// }

