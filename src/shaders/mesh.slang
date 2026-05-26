import include.scene;

struct VertexUniformData {
  float4x4 render_matrix;
};

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

struct MaterialData {
  float4 colorFactors;
  // Add other material data fields here
};

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

  Fragment output;

  output.position =
      mul(scene.sceneData.viewproj, mul(storageBuffer.uniforms.render_matrix,
                                        float4(input.position, 1.0)));

  // output.position.xy = input.position.xy * storageBuffer.uniforms.Scale +
  //                      storageBuffer.uniforms.Translate;
  // output.position.zw = float2(input.position.z, 1.0);

  output.normal = input.normal;

  output.color = input.color.xyz;

  output.uv.x = input.uv_x;
  output.uv.y = input.uv_y;

  return output;
}

// Actual frament shader, using array for layered textured (atlas)
[shader("fragment")]
float4 fragment(Fragment input) : SV_Target {
  // [DEBUG] Output vertex color directly — bypasses texture to confirm
  // geometry. If all 3 meshes appear with their vertex colors, remove this and
  // restore the texture path below.
  // return float4(input.color, 1.0);
  int colorID = material.data.colorTexID;
  float3 color = input.color * scene.allTextures[colorID].Sample(input.uv).xyz;
  return float4(color, 1.0);
}

