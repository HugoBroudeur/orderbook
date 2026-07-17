import include.scene;

struct OutFragment {
  float4 pos : SV_POSITION;
  float3 uvw;
};

struct StorageBuffer {
  float4x4 model;
  Vertex *vertexBuffer;
}

struct SkyboxData {
  uint cubeTexId;
}

[[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer;

public[[vk::binding(0, 0)]]
ParameterBlock<BindlessSceneParams> scene;

struct SkyboxParams {
  ConstantBuffer<SkyboxData> data;
};

[shader("vertex")]
OutFragment vertex(uint vertexID: SV_VertexID) {
  Vertex input = storageBuffer.vertexBuffer[vertexID];
  OutFragment output;
  output.uvw = input.position;

  // Convert cubemap coordinates into Vulkan coordinate space
  output.uvw.xy *= -1.0;

  // Remove translation from view matrix
  float4x4 viewMat = storageBuffer.model;
  viewMat[0][3] = 0.0;
  viewMat[1][3] = 0.0;
  viewMat[2][3] = 0.0;
  output.pos =
      mul(scene.sceneData.proj, mul(viewMat, float4(input.position.xyz, 1.0)));

  return output;
}

[shader("fragment")]
float4 fragment(OutFragment input) {
  return float4(1, 1, 1, 1);
  // data.Sample(input.uvw);
}
