module scene;

// struct SceneData {
//   float4x4 view;
//   float4x4 proj;
//   float4x4 viewproj;
//   float4 ambientColor;
//   float4 sunlightDirection; // w for sun power
//   float4 sunlightColor;
// };
//
// struct GLTFMaterialData {
//   float4 colorFactors;
//   float4 metal_rough_factors;
//   int colorTexID;
//   int metalRoughTexID;
// };
//
// [[vk::binding(0, 0)]]
// ConstantBuffer<SceneData> sceneData;
//
// #ifdef USE_BINDLESS
// [[vk::binding(1, 0)]]
// Sampler2D allTextures[];
// #else
// [[vk::binding(1, 1)]]
// Sampler2D colorTex;
// [[vk::binding(2, 1)]]
// Sampler2D metalRoughTex;
// #endif
//
// [[vk::binding(0, 1)]]
// ConstantBuffer<GLTFMaterialData> materialData;
//
//
//
//

public struct SceneData {
  public float4x4 view;
  public float4x4 proj;
  public float4x4 viewproj;
  public float4 ambientColor;
  public float4 sunlightDirection;
  public float4 sunlightColor;
};

public struct GLTFMaterialData {
  public float4 colorFactors;
  public float4 metal_rough_factors;
  public int colorTexID;
  public int metalRoughTexID;
};

// Interface defining what any SceneParams implementation must provide
public interface ISceneParams {
  Sampler2D getColorTex(int index);
  Sampler2D getMetalRoughTex(int index);
  ConstantBuffer<SceneData> getSceneData();
};

// --- Bindless implementation ---
public struct BindlessSceneParams : ISceneParams {
  public ConstantBuffer<SceneData> sceneData;
  public Sampler2D allTextures[];

  public ConstantBuffer<SceneData> getSceneData() { return sceneData; }
  public Sampler2D getColorTex(int index) { return allTextures[index]; }
  public Sampler2D getMetalRoughTex(int index) { return allTextures[index]; }
};

// --- Non-bindless implementation ---
public struct BoundSceneParams : ISceneParams {
  public ConstantBuffer<SceneData> sceneData;
  public Sampler2D colorTex;
  public Sampler2D metalRoughTex;

  public ConstantBuffer<SceneData> getSceneData() { return sceneData; }
  public Sampler2D getColorTex(int index) { return colorTex; }
  public Sampler2D getMetalRoughTex(int index) { return metalRoughTex; }
};

public struct MaterialParams {
  public ConstantBuffer<GLTFMaterialData> data;
};

