import include.scene;

struct InVertex {
  float3 pos;
  float3 normal;
};

struct OutFragment {
  float4 position : SV_Position;
  float3 world_position;
  float3 normal;
  float lod_bias;
  float3 light;
};

struct StorageBuffer {
  float4x4 model;
  InVertex *vertexBuffer;
}

[[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer;

public[[vk::binding(0, 0)]]
ParameterBlock<BindlessSceneParams> scene;

SamplerCube colorTex;

[shader("vertex")]
OutFragment vertex(uint vertexID: SV_VertexID) {
  InVertex input = storageBuffer.vertexBuffer[vertexID];
  OutFragment output;

  float4 position = float4(input.pos, 1.0);

  float4 world_position = mul(storageBuffer.model, position);
  output.world_position = world_position.xyz;

  output.position = mul(scene.sceneData.viewproj, world_position);

  output.normal = mul((float3x3)storageBuffer.model, input.normal);
  output.lod_bias = scene.sceneData.lodBias;

  // float3 light_position = float3(0.0f, -5.0f, 5.0f);
  // output.LightVec = lightPos.xyz - output.WorldPos.xyz;
  // output.ViewVec = -output.WorldPos;

  return output;
}

[shader("fragment")]
float4 fragment(Fragment input) { return colorTex.Sample(input.position.xyz); }
