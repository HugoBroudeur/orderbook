[[vk::binding(0, 0)]]
[vk::image_format("rgba16f")]
RWTexture2D<float4> image;

struct PushConstants {
  float4 data1;
  float4 data2;
  float4 data3;
  float4 data4;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

// Return random noise in the range [0.0, 1.0], as a function of x.
float Noise2d(in float2 x) {
  float xhash = cos(x.x * 37.0);
  float yhash = cos(x.y * 57.0);
  return frac(415.92653 * (xhash + yhash));
}

// Convert Noise2d() into a "star field" by stomping everything below fThreshold
// to zero.
float NoisyStarField(in float2 vSamplePos, float fThreshold) {
  float StarVal = Noise2d(vSamplePos);
  if (StarVal >= fThreshold)
    StarVal = pow((StarVal - fThreshold) / (1.0 - fThreshold), 6.0);
  else
    StarVal = 0.0;
  return StarVal;
}

// Stabilize NoisyStarField() by only sampling at integer values.
float StableStarField(in float2 vSamplePos, float fThreshold) {
  // Linear interpolation between four samples.
  float fractX = frac(vSamplePos.x);
  float fractY = frac(vSamplePos.y);
  float2 floorSample = floor(vSamplePos);

  float v1 = NoisyStarField(floorSample, fThreshold);
  float v2 = NoisyStarField(floorSample + float2(0.0, 1.0), fThreshold);
  float v3 = NoisyStarField(floorSample + float2(1.0, 0.0), fThreshold);
  float v4 = NoisyStarField(floorSample + float2(1.0, 1.0), fThreshold);

  float StarVal = v1 * (1.0 - fractX) * (1.0 - fractY) +
                  v2 * (1.0 - fractX) * fractY + v3 * fractX * (1.0 - fractY) +
                  v4 * fractX * fractY;
  return StarVal;
}

void mainImage(out float4 fragColor, in float2 fragCoord) {
  uint width, height;
  image.GetDimensions(width, height);
  float2 iResolution = float2(width, height);

  // Sky Background Color
  float3 vColor = float3(0.1, 0.2, 0.4) * fragCoord.y  / iResolution.y;
  // float3 vColor = pushConstants.data1.xyz * fragCoord.y / iResolution.y;

  // Note: Choose fThreshold in the range [0.99, 0.9999].
  // Higher values (i.e., closer to one) yield a sparser starfield.
  // float StarFieldThreshold = pushConstants.data1.w;
  float StarFieldThreshold = 0.99;

  // Stars with a slow crawl.
  float xRate = 0.2;
  float yRate = -0.06;
  float2 vSamplePos = fragCoord.xy + float2(xRate * 1.0, yRate * 1.0);
  float StarVal = StableStarField(vSamplePos, StarFieldThreshold);
  vColor += float3(StarVal, StarVal, StarVal);

  fragColor = float4(vColor, 1.0);
}

[shader("compute")]
[numthreads(16, 16, 1)]
void compute(uint3 globalID: SV_DispatchThreadID) {
  int2 texelCoord = int2(globalID.xy);

  uint width, height;
  image.GetDimensions(width, height);
  int2 size = int2(width, height);

  if (texelCoord.x < size.x && texelCoord.y < size.y) {
    float4 color;
    mainImage(color, float2(texelCoord));

    image[texelCoord] = color;
  }
}
