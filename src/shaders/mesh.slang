import scene;

struct VertexUniformData {
  float4x4 render_matrix;
  float2 Translate;
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
  // return input.Color * Texture.Sample(Sampler, input.TexCoord);

  // float lightValue = max(dot(inNormal, vec3(0.3f,1.f,0.3f)), 0.1f);
  //
  // vec3 irradiance = calcIrradiance(inNormal);
  //

  // vec3 color = inColor * texture(colorTex,inUV).xyz;
  int colorID = material.data.colorTexID;
  float3 color = input.color * scene.allTextures[colorID].Sample(input.uv).xyz;

  // outFragColor =
  //     vec4(color * lightValue + color * irradiance.x * vec3(0.2f), 1.0f);
  return float4(color, 1.0);

  // return float4(input.color, 1.0) *
  //        checkerTexture.Sample(
  //            input.uv); 
  // return input.Color;
  //  return float4(input.TexCoord, 0, 1);
}
