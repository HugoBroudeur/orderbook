// Descriptor binding for the output image
[[vk::binding(0, 0)]]
[vk::image_format("rgba16f")]
RWTexture2D<float4> image;
// Texture2D<float4> image : register(c, space0);

[shader("compute")]
[numthreads(16, 16, 1)]
void compute(uint3 globalID: SV_DispatchThreadID,
             uint3 localID: SV_GroupThreadID) {
  int2 texelCoord = int2(globalID.xy);
  int2 size;
  image.GetDimensions(size.x, size.y);

  if (texelCoord.x < size.x && texelCoord.y < size.y) {
    float4 color = float4(0.0, 0.0, 0.0, 1.0);

    if (localID.x != 0 && localID.y != 0) {
      color.x = float(texelCoord.x) / float(size.x);
      color.y = float(texelCoord.y) / float(size.y);
    }

    image[texelCoord] = color;
  }
}
