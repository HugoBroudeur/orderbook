import include.scene;
import include.lights;
import include.math;

struct StorageBuffer {
  float4x4 render_matrix;
  Vertex *vertexBuffer;
  uint materialBufferSlot;
  uint materialIdx;
}

[[vk::push_constant]]
ConstantBuffer<StorageBuffer> storageBuffer;

ParameterBlock<BindlessSceneParams> scene;

[shader("vertex")]
Fragment vertex(uint vertexID: SV_VertexID) {
  Vertex input = storageBuffer.vertexBuffer[vertexID];

  float4 position = float4(input.position, 1.0);

  Fragment output;

  float4 world_position = mul(storageBuffer.render_matrix, position);
  output.world_position = world_position.xyz;

  output.position = mul(scene.sceneData.viewproj, world_position);

  output.normal = mul(storageBuffer.render_matrix, float4(input.normal, 0)).xyz;

  MaterialData material = scene.getMaterial(storageBuffer.materialBufferSlot,
                                            storageBuffer.materialIdx);

  output.color = input.color.xyz * material.colorFactors.xyz * input.color.w;

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
  MaterialData material = scene.getMaterial(storageBuffer.materialBufferSlot,
                                            storageBuffer.materialIdx);

  float4 colorTex = scene.allTextures[material.colorTexID].Sample(input.uv);
  float4 occlusionTex =
      scene.allTextures[material.occlusionTexID].Sample(input.uv);
  float4 emissiveTex =
      scene.allTextures[material.emissiveTexID].Sample(input.uv);
  float4 normalTex = scene.allTextures[material.normalTexID].Sample(input.uv);
  float4 metalRoughnessTex =
      scene.allTextures[material.metalRoughTexID].Sample(input.uv);
  float4 transmissionTex =
      scene.allTextures[material.transmissionTexId].Sample(input.uv);

  float3 color = input.color * colorTex.xyz;

  float transmission = transmissionTex.r * material.transmissionFactor;
  // Coverage alpha, with the transmission mask folded in only to the degree
  // the material is transmissive: opaque materials (factor 0) keep full
  // coverage, transmissive ones (e.g. light shafts) fade by their
  // transmission texture — this asset authors shaft falloff through it.
  float alpha = colorTex.a * material.colorFactors.a *
                lerp(1.0f, transmissionTex.r, material.transmissionFactor);

  float ao = occlusionTex.r;
  float roughness = metalRoughnessTex.g * material.metalRoughFactors.y;
  float metallic = metalRoughnessTex.b * material.metalRoughFactors.x;

  // Slot 0 is the white "no texture" fallback, and white decodes to a
  // 45°-bent tangent-space normal — so normalTexID 0 means "no normal map":
  // use the geometric normal instead.
  float3 nTS = material.normalTexID == 0
      ? float3(0.0, 0.0, 1.0)
      : normalize((normalTex.xyz * 2.0) - 1.0);
  float3 normalViewSpace = mul(input.TBNMatrix, nTS);

  float3 viewDir = normalize(input.cameraPos - input.world_position);

  // Exponent 2..2048. The old linear max(1, (1-r)*256) bottomed out at
  // exponent 1, where pow(NdotH, 1) is a huge bright lobe — rough surfaces
  // washed out with specular instead of losing it.
  float shininess = exp2((1.0f - roughness) * 10.0f + 1.0f);
  // Dielectrics reflect ~4% (F0) and roughness dims that quickly; metals'
  // entire appearance IS their reflection (diffuse is killed by metallic
  // below), so they keep most of their specular energy even fully rough —
  // the exp2 exponent above spreads the lobe instead. Without this split,
  // rough metals read as stone.
  float specStrength = lerp(0.04f * (1.0f - 0.75f * roughness), // dielectric
                            1.0f - 0.3f * roughness,            // metal
                            metallic);

  AmbientLight ambientLight = makeAmbiantLight(scene.sceneData.ambientColor);
  Lighting ambientLit = calculateLighting(ambientLight, input.world_position,
                                          normalViewSpace, viewDir, shininess);

  DirectionalLight sun = makeSun(scene.sceneData.sunlightDirection.xyz,
                                 scene.sceneData.sunlightColor,
                                 scene.sceneData.sunlightSpecularColor);

  // One call gives you both diffuse and specular
  Lighting sunLit = calculateLighting(sun, input.world_position,

                                      normalViewSpace, viewDir, shininess);

  float3 diffuse = color * (1.0f - metallic) * (1 - transmission);
  float3 ambient = color * ambientLit.Diffuse * ao;

  // Metals tint their reflection with their own color; dielectrics don't.
  float3 specTint = lerp(float3(1.0), color, metallic);

  // Emissive color
  float3 emissive = emissiveTex.rgb * material.emissiveFactors.xyz *
                    material.emissiveFactors.w;
  // emissive *= alpha;

  return float4(diffuse * sunLit.Diffuse +
                    sunLit.Specular * specTint * specStrength + ambient +
                    emissive,
                alpha);

  // return float4(alpha, alpha, alpha,  1);
}
