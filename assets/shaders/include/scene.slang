module scene;

public struct Vertex {
  public float3 position : POSITION;
  public float1 uv_x;
  public float3 normal;
  public float1 uv_y;
  public float4 color : COLOR1;
  public float3 tangent;
  public float1 _unused;
};

public struct Fragment {
  public float4 position : SV_Position;
  public float3 world_position;
  public float3 normal;
  public float3 color : COLOR1;
  public float2 uv;
  public float3 tangent;
  public float3x3 TBNMatrix;
  public float3 cameraPos;
}

public struct SceneData {
  public float4x4 view;
  public float4x4 proj;
  public float4x4 viewproj;
  public float4 ambientColor;
  public float4 sunlightDirection;
  public float4 sunlightColor;
  public float4 sunlightSpecularColor;
  public float time;
  public float lodBias;
};

public struct MaterialData {
  public float4 colorFactors;
  public float4 metalRoughFactors;
  public float4 emissiveFactors;
  public float transmissionFactor;
  public uint colorTexID;
  public uint metalRoughTexID;
  public uint normalTexID;
  public uint occlusionTexID;
  public uint emissiveTexID;
  public uint transmissionTexId;
  // 16 public float4 metal_rough_factors; public int metalRoughTexID;
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
  public ConstantBuffer<MaterialData> data;
};

public struct SimpleSceneParams {
  public ConstantBuffer<SceneData> sceneData;

  public ConstantBuffer<SceneData> getSceneData() { return sceneData; }
}
