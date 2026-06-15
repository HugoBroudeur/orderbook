import include.scene;

struct Vertex {
  float3 position : POSITION;
  float1 uv_x;
  float3 normal;
  float1 uv_y;
  float4 color : COLOR1;
};

struct Fragment {
  float4 position : SV_Position;
  float3 normal;
  float3 color : COLOR1;
  float2 uv;
}

struct VertexBuffer {
  Vertex *vertices;
};

struct StorageBuffer {
  float4x4 render_matrix;
  Vertex *vertexBuffer;
}

// This defines slot 0, space1 for the vertex stage
// ConstantBuffer<StorageBuffer> storageBuffer : register(b0, space1);
[[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer;

// Texture and sampler
// [[vk::binding(0, 0)]]
// Sampler2D uvTexture : register(s1, space0);
// [[vk::binding(1, 1)]]
// Sampler2D checkerTexture : register(s1, space0);

public[[vk::binding(0, 0)]]
ParameterBlock<BindlessSceneParams> scene;
public[[vk::binding(0, 1)]]
ParameterBlock<MaterialParams> material;

[shader("vertex")]
Fragment vertex(uint vertexID: SV_VertexID) {
  Vertex input = storageBuffer.vertexBuffer[vertexID];

  float4 position = float4(input.position, 1.0);

  Fragment output;

  output.position =
      mul(scene.sceneData.viewproj, mul(storageBuffer.render_matrix, position));
  output.normal = mul(storageBuffer.render_matrix, float4(input.normal, 0)).xyz;

  output.color = input.color.xyz * material.data.colorFactors.xyz;

  output.uv.x = input.uv_x;
  output.uv.y = input.uv_y;

  return output;
}

[shader("fragment")]
float4 fragment(Fragment input) : SV_Target {
  int colorID = material.data.colorTexID;

  float lightValue = max(dot(input.normal, scene.sceneData.sunlightDirection.xyz), 0.1f);

  float3 color = input.color * scene.allTextures[colorID].Sample(input.uv).xyz;
  float3 ambient = color * scene.sceneData.ambientColor.xyz;

  return float4(color * lightValue * scene.sceneData.sunlightColor.w + ambient, 1.0f);
}

