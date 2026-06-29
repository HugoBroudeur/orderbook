import include.scene;
import include.lights;
import include.math;

struct VertexBuffer {
  Vertex *vertices;
};

struct StorageBuffer {
  float4x4 render_matrix;
  Vertex *vertexBuffer;
}

[[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer;

public[[vk::binding(0, 0)]]
ParameterBlock<BindlessSceneParams> scene;
public[[vk::binding(0, 1)]]
ParameterBlock<MaterialParams> material;

[shader("vertex")]
Fragment vertex(uint vertexID: SV_VertexID) {
  Vertex input = storageBuffer.vertexBuffer[vertexID];

  float4 position = float4(input.position, 1.0);

  Fragment output;

  float4 world_position = mul(storageBuffer.render_matrix, position);
  output.world_position = world_position.xyz;

  output.position = mul(scene.sceneData.viewproj, world_position);

  output.normal = mul(storageBuffer.render_matrix, float4(input.normal, 0)).xyz;

  output.color = input.color.xyz * material.data.colorFactors.xyz;

  output.uv.x = input.uv_x;
  output.uv.y = input.uv_y;

  return output;
}

[shader("fragment")]
float4 fragment(Fragment input) : SV_Target {
  int colorID = material.data.colorTexID;
  int mrID = int(material.data.metalRoughTexID);
  float4 mr = scene.allTextures[mrID].Sample(input.uv);

  float ao = mr.r;
  float roughness = mr.g * material.data.metalRoughFactors.y;
  float metallic = mr.b * material.data.metalRoughFactors.x;

  float3 color = input.color * scene.allTextures[colorID].Sample(input.uv).xyz;

  float3 N = normalize(input.normal);

  float3 cameraPos = calculateCameraPosition(scene.sceneData.view);
  float3 viewDir = normalize(cameraPos - input.world_position);

  float shininess = max(1.0f, (1.0f - roughness) * 256.0f);

  AmbientLight ambientLight = makeAmbiantLight(scene.sceneData.ambientColor);
  Lighting ambientLit = calculateLighting(ambientLight, input.world_position, N,
                                          viewDir, shininess);

  DirectionalLight sun = makeSun(scene.sceneData.sunlightDirection.xyz,
                                 scene.sceneData.sunlightColor);

  // One call gives you both diffuse and specular
  Lighting sunLit =
      calculateLighting(sun, input.world_position, N, viewDir, shininess);

  float3 diffuse = color * (1.0f - metallic);
  float3 ambient = color * ambientLit.Diffuse * ao;
  // float3 ambient = color * scene.sceneData.ambientColor.rgb *
  //                  scene.sceneData.ambientColor.a * ao;

  return float4(diffuse * sunLit.Diffuse + sunLit.Specular + ambient, 1.0f);
}
