struct VS_Input {
  float2 Position : POSITION;
  float2 TexCoord : TEXCOORD0;
  float4 Color : COLOR1;
};

struct PS_Input {
  float4 Position : SV_Position;
  float4 Color : COLOR1;
  float2 TexCoord : TEXCOORD0;
};

// This defines slot 0, space1 for the vertex stage
// ConstantBuffer<VertexUniformData> vu : register(b0, space1);

[shader("vertex")]
PS_Input vertex(uint vertexID: SV_VertexID) {
  PS_Input output;
  // output.TexCoord = input.TexCoord;
  // output.Color = input.Color;
  // output.Position.xy = input.Position;
  // output.Position.zw = float2(0.5, 1);

  // Force triangle to specific positions (ignore input)
  if (vertexID == 0) {
    output.Position = float4(-0.5, 0.5, 0.5, 1);
    output.Color = float4(1, 0, 0, 1);
  } else if (vertexID == 1) {
    output.Position = float4(0, -0.5, 0.5, 1);
    output.Color = float4(0, 1, 0, 1);
  } else {
    output.Position = float4(0.5, 0.5, 0.5, 1);
    output.Color = float4(0, 0, 1, 1);
  }
  output.TexCoord = float2(0,     1);

  return output;
}

[shader("fragment")]
float4 fragment(PS_Input input) : SV_Target {

  return float4(input.Color); // Debug show red
  // return input.Color;
}
