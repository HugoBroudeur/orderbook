static const float3 positions[3] = {
  // float2(0.0, -0.5),
  // float2(0.5, 0.5),
  // float2(-0.5, 0.5),
  float3(-0.5, -0.5, -2.0),
  float3(0.0, 0.5, -2.0),
  float3(0.5, -0.5, -2.0),
};

static const float3 colors[3] = {
  float3(1.0, 0.0, 0.0),
  float3(0.0, 1.0, 0.0),
  float3(0.0, 0.0, 1.0),
};

struct VSOutput {
  float4 PositionCS : SV_Position;
  float3 Color : VertexColor;
};

struct VertexUniformData {
  float4x4 proj_matrix;
  // float4 view_matrix;
};

// This defines slot 0, space1 for the vertex stage
ConstantBuffer<VertexUniformData> vu : register(b0, space1);

[shader("vertex")]
VSOutput vertex(uint vertexID: SV_VertexID) {
  VSOutput output;
  // output.PositionCS = float4(positions[vertexID], 1.0);
  output.PositionCS = mul(vu.proj_matrix, float4(positions[vertexID], 1.0));
  output.Color = colors[vertexID];
  return output;
}

[shader("fragment")]
float4 fragment(float3 color: VertexColor) : SV_Target {
  return float4(color.rgb, 1.0);
}
