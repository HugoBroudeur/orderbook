struct VertexUniformData {
  float2 Scale;
  float2 Translate;
};

struct Vertex {
  float2 Position : POSITION;
  float2 TexCoord : TEXCOORD0;
  float4 Color : COLOR1;
};

struct PS_Input {
  float4 Position : SV_Position;
  float4 Color : COLOR1;
  float2 TexCoord : TEXCOORD0;
};

struct SceneData {
  float4x4 viewproj;
  // Add other scene data fields here
};

struct MaterialData {
  float4 colorFactors;
  // Add other material data fields here
};

// struct VertexBuffer {
//   StructuredBuffer<Vertex> vertices;
// };

struct StorageBuffer {
  VertexUniformData uniforms;
  // VertexBuffer vertexBuffer;
  uint64_t vertexBufferAddress;
}

// This defines slot 0, space1 for the vertex stage
// [[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer : register(b0, space1);

Texture2D<float4> Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

// Descriptor bindings (replace with your actual set/binding)
// [[vk::binding(0, 0)]]
// ConstantBuffer<SceneData> sceneData;

// [[vk::binding(1, 0)]]
// ConstantBuffer<MaterialData> materialData;

// This defines slot 0, space1 for the vertex stage
// ConstantBuffer<VertexUniformData> vu : register(b0, space1);

[shader("vertex")]
PS_Input vertex(uint vertex_index: SV_VertexID) {

  // Create pointer from device address
  Vertex *vertexBuffer =
      reinterpret<Vertex *>(storageBuffer.vertexBufferAddress);

  // Load vertex data
  Vertex input = vertexBuffer[vertex_index];

  // Vertex input = storageBuffer.vertexBuffer.vertices[vertex_index];
  PS_Input output;
  output.TexCoord = input.TexCoord;
  output.Color = input.Color;
  // output.Position.xy = input.Position;
  output.Position.xy = input.Position * storageBuffer.uniforms.Scale +
                       storageBuffer.uniforms.Translate;

  output.Position.zw = float2(0, 1);
  return output;
}

// Actual frament shader, using array for layered textured (atlas)
[shader("fragment")]
float4 fragment(PS_Input input) : SV_Target {
  // return input.Color * Texture.Sample(Sampler, input.TexCoord);
  // return float4(1, 0, 0, 1); // Debug show red
  return input.Color;
}
