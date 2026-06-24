import scene;

public struct Lighting {
  public float3 Diffuse;
  public float3 Specular;
};

public interface ILight {
  float3 position();
  Lighting illuminate(float3 worldPos, float3 normal, float3 viewDir,
                      float specularHardness);
  bool isCullable(float3 worldPos);
};

public struct PointLight : ILight {
  public float3 pos;
  public float3 diffuseColor;
  public float diffusePower;
  public float3 specularColor;
  public float specularPower;

  float3 position() { return pos; }

  Lighting illuminate(float3 worldPos, float3 normal, float3 viewDir,
                      float specularHardness) {
    Lighting OUT;
    if (diffusePower > 0) {
      float3 lightDir = pos - worldPos;
      float dist = length(lightDir);
      lightDir = lightDir / dist;
      float dist2 = dist * dist;

      float NdotL = dot(normal, lightDir);
      float diffuseIntensity = saturate(NdotL);
      OUT.Diffuse = diffuseIntensity * diffuseColor * diffusePower / dist2;

      float3 H = normalize(lightDir + viewDir);
      float NdotH = dot(normal, H);
      float specularIntensity = pow(saturate(NdotH), specularHardness);
      OUT.Specular = specularIntensity * specularColor * specularPower / dist2;
    }
    return OUT;
  }

  bool isCullable(float3 worldPos) { return diffusePower <= 0; }
};

public DirectionalLight makeSun(float3 direction, float4 color) {
  DirectionalLight sun;
  sun.dir = direction;
  sun.diffuseColor = color.xyz;
  sun.diffusePower = color.w;
  sun.specularColor = float3(1.0f, 1.0f, 1.0f);
  sun.specularPower = 1.0f;

  return sun;
}

public struct DirectionalLight : ILight {
  public float3 dir;
  public float3 diffuseColor;
  public float diffusePower;
  public float3 specularColor;
  public float specularPower;

  float3 position() { return dir * 1e6; }

  bool isCullable(float3 worldPos) { return false; }

  Lighting illuminate(float3 worldPos, float3 normal, float3 viewDir,
                      float specularHardness) {
    Lighting OUT;
    float3 lightDir = normalize(dir);

    float NdotL = dot(normal, lightDir);
    OUT.Diffuse = saturate(NdotL) * diffuseColor * diffusePower;

    float3 H = normalize(lightDir + viewDir);
    float NdotH = dot(normal, H);
    OUT.Specular =
        pow(saturate(NdotH), specularHardness) * specularColor * specularPower;
    return OUT;
  }
};

struct SHCoefficients {
  float3 l00, l1m1, l10, l11, l2m2, l2m1, l20, l21, l22;
};

public struct AmbientLight : ILight {
  static const SHCoefficients c = {
    float3(0.3623915, 0.2624130, 0.2326261),
    float3(0.1759131, 0.1436266, 0.1260569),
    float3(-0.0247311, -0.0101254, -0.0010745),
    float3(0.0346500, 0.0223184, 0.0101350),
    float3(0.0198140, 0.0144073, 0.0043987),
    float3(-0.0469596, -0.0254485, -0.0117786),
    float3(-0.0898667, -0.0760911, -0.0740964),
    float3(0.0050194, 0.0038841, 0.0001374),
    float3(-0.0818750, -0.0321501, 0.0033399),
  };

  float3 position() { return float3(0.0f, 0.0f, 0.0f); }

  bool isCullable(float3 worldPos) { return false; }

  Lighting illuminate(float3 worldPos, float3 normal, float3 viewDir,
                      float specularHardness) {
    Lighting OUT;
    const float c1 = 0.429043;
    const float c2 = 0.511664;
    const float c3 = 0.743125;
    const float c4 = 0.886227;
    const float c5 = 0.247708;
    OUT.Diffuse =
        (c1 * c.l22 * (normal.x * normal.x - normal.y * normal.y) +
         c3 * c.l20 * normal.z * normal.z + c4 * c.l00 - c5 * c.l20 +
         2.0 * c1 * c.l2m2 * normal.x * normal.y +
         2.0 * c1 * c.l21 * normal.x * normal.z +
         2.0 * c1 * c.l2m1 * normal.y * normal.z + 2.0 * c2 * c.l11 * normal.x +
         2.0 * c2 * c.l1m1 * normal.y + 2.0 * c2 * c.l10 * normal.z);

    return OUT;
  };
}

public Lighting calculateLighting<T : ILight>(T light, float3 worldPos,
                                              float3 normal, float3 viewDir,
                                              float specularHardness) {
  return light.illuminate(worldPos, normal, viewDir, specularHardness);
}

