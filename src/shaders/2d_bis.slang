import include.scene;

struct VertexUniformData {
  float4x4 render_matrix;
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
  Vertex *vertexBuffer;
}

// This defines slot 0, space1 for the vertex stage
// ConstantBuffer<StorageBuffer> storageBuffer : register(b0, space1);
[[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer;

// public[[vk::binding(0, 0)]]
// ParameterBlock<BindlessSceneParams> scene;
public[[vk::binding(0, 0)]]
ParameterBlock<SimpleSceneParams> scene;

// Texture and sampler
// Sampler2D uvTexture : register(s0, space0);
// Sampler2D checkerTexture : register(s1, space0);

[shader("vertex")]
PS_Input vertex(uint vertexID: SV_VertexID) {
  Vertex input = storageBuffer.vertexBuffer[vertexID];

  PS_Input output;

  // output.Position.xy = input.Position * storageBuffer.uniforms.Scale +
  //                      storageBuffer.uniforms.Translate;
  // output.Position.zw = float2(0.0, 1.0);

  output.Position = mul(scene.sceneData.viewproj, float4(input.Position, 1.0));
  // output.Position = mul(scene.sceneData.viewproj,
  // float4(input.Position, 1.0)); output.Position =
  //     mul(storageBuffer.uniforms.render_matrix, float4(input.Position, 1.0));

  // if (vertexID == 0) {
  //   output.Position = float4(input.Position, 1.0);
  //   // output.Position = float4(-1, 1, 1, 1);
  // } else if (vertexID == 1) {
  //   output.Position = float4(input.Position, 1.0);
  //   // output.Position = float4(0, -1, 1, 1);
  // } else if (vertexID == 2) {
  //   output.Position = float4(input.Position, 1.0);
  //   // output.Position = float4(1, 1, 1, 1);
  // }

  output.Color = input.Color;

  output.TexCoord = input.TexCoord;

  return output;
}

// Actual frament shader, using array for layered textured (atlas)
[shader("fragment")]
float4 fragment(PS_Input input) : SV_Target {
  // return input.Color * Texture.Sample(Sampler, input.TexCoord);

  // return input.Color * uvTexture.Sample(input.TexCoord);
  // return input.Color * scene.getColorTex(0).Sample(input.TexCoord);
  return input.Color;

  // return input.Color;
  //  return float4(input.TexCoord, 0, 1);
}

