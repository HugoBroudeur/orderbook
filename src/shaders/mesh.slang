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
//   StructuredBuffer<Vertex, Std430DataLayout> vertices;
// };

struct VertexBuffer {
  Vertex *vertices;
};

struct StorageBuffer {
  VertexUniformData uniforms;
  // VertexBuffer vertexBuffer;
  // VertexBuffer *vertexBuffer;
  // uint64_t vertexBuffer;
  Vertex *vertexBuffer;
  // ConstBufferPointer<VertexBuffer> vertexBuffer;
  // ConstBufferPointer<Vertex *> vertexBuffer;
}

// uniform float3* ptr_vec3;
// uniform float4* ptr_vec4;
//
// [shader("compute")]
// [numthreads(1,1,1)]
// void computeMain(uint3 threadId : SV_DispatchThreadID) {
//     ptr_vec3[1] = float3(0);
//     ptr_vec4[1] = float4(0);

// This defines slot 0, space1 for the vertex stage
// ConstantBuffer<StorageBuffer> storageBuffer : register(b0, space1);
[[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer;

// Texture and sampler
Sampler2D uvTexture : register(s0, space0);
Sampler2D checkerTexture : register(s1, space0);

// Descriptor bindings (replace with your actual set/binding)
// [[vk::binding(0, 0)]]
// ConstantBuffer<SceneData> sceneData;

// [[vk::binding(1, 0)]]
// ConstantBuffer<MaterialData> materialData;

// This defines slot 0, space1 for the vertex stage
// ConstantBuffer<StorageBuffer> storageBuffer : register(b0, space1);

[shader("vertex")]
PS_Input vertex(uint vertexID: SV_VertexID) {
  Vertex input = storageBuffer.vertexBuffer[vertexID];

  PS_Input output;

  output.Position.xy = input.Position * storageBuffer.uniforms.Scale +
                       storageBuffer.uniforms.Translate;
  output.Position.zw = float2(0.0, 1.0);

  output.Color = input.Color;

  output.TexCoord = input.TexCoord;

  return output;
}

// Actual frament shader, using array for layered textured (atlas)
[shader("fragment")]
float4 fragment(PS_Input input) : SV_Target {
  // return input.Color * Texture.Sample(Sampler, input.TexCoord);

  return input.Color * uvTexture.Sample(input.TexCoord);

  // The checker texture works, can be used for debug
  return input.Color * checkerTexture.Sample(input.TexCoord);

  // return input.Color;
   //  return float4(input.TexCoord, 0, 1);
}
