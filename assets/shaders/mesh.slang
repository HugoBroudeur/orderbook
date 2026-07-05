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

  output.color =
      input.color.xyz * material.data.colorFactors.xyz * input.color.w;

  output.uv.x = input.uv_x;
  output.uv.y = input.uv_y;

  output.tangent =
      mul(storageBuffer.render_matrix, float4(input.tangent, 0)).xyz;

  output.TBNMatrix = computeTBNMatrix(output.tangent, output.normal);
  output.cameraPos = calculateCameraPosition(scene.sceneData.view);

  return output;
}

[shader("fragment")]
float4 fragment(Fragment input) : SV_Target {
  float4 colorTex =
      scene.allTextures[material.data.colorTexID].Sample(input.uv);
  float4 occlusionTex =
      scene.allTextures[material.data.occlusionTexID].Sample(input.uv);
  float4 emissiveTex =
      scene.allTextures[material.data.emissiveTexID].Sample(input.uv);
  float4 normalTex =
      scene.allTextures[material.data.normalTexID].Sample(input.uv);
  float4 metalRoughnessTex =
      scene.allTextures[material.data.metalRoughTexID].Sample(input.uv);
  float4 transmissionTex =
      scene.allTextures[material.data.transmissionTexId].Sample(input.uv);

  float3 color = input.color * colorTex.xyz;

  float transmission = transmissionTex.r * material.data.transmissionFactor;
  float alpha = colorTex.a * material.data.colorFactors.a * (transmission);

  float ao = occlusionTex.r;
  float roughness = metalRoughnessTex.g * material.data.metalRoughFactors.y;
  float metallic = metalRoughnessTex.b * material.data.metalRoughFactors.x;
  float3 normalViewSpace =
      mul(input.TBNMatrix, normalize((normalTex.xyz * 2.0) - 1.0));

  float3 viewDir = normalize(input.cameraPos - input.world_position);

  float shininess = max(1.0f, (1.0f - roughness) * 256.0f);

  AmbientLight ambientLight = makeAmbiantLight(scene.sceneData.ambientColor);
  Lighting ambientLit = calculateLighting(ambientLight, input.world_position,
                                          normalViewSpace, viewDir, shininess);

  DirectionalLight sun = makeSun(scene.sceneData.sunlightDirection.xyz,
                                 scene.sceneData.sunlightColor,
                                 scene.sceneData.sunlightSpecularColor);

  // One call gives you both diffuse and specular
  Lighting sunLit = calculateLighting(sun, input.world_position,

                                      normalViewSpace, viewDir, shininess);

  float3 diffuse = color * (1.0f - metallic);
  float3 ambient = color * ambientLit.Diffuse * ao;

  // Metals tint their reflection with their own color; dielectrics don't.
  float3 specTint = lerp(float3(1.0), color, metallic);

  // Emissive color
  float3 emissive = emissiveTex.rgb * material.data.emissiveFactors.xyz *
                    material.data.emissiveFactors.w;
  // emissive *= alpha;

  return float4(diffuse * sunLit.Diffuse + sunLit.Specular * specTint +
                    ambient + emissive,
                alpha);

  // return float4(alpha, alpha, alpha,  1);
}
