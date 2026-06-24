public float3 calculateCameraPosition(float4x4 view) {
  float3x3 R = float3x3(view[0].xyz, view[1].xyz, view[2].xyz);
  float3 t = view[3].xyz;
  float3 cameraPos = -mul(transpose(R), t);

  return cameraPos;
}

public float3x3 inverse3x3(float3x3 m) {
  float3 c0 = cross(m[1].xyz, m[2].xyz);
  float3 c1 = cross(m[2].xyz, m[0].xyz);
  float3 c2 = cross(m[0].xyz, m[1].xyz);
  float det = dot(m[0].xyz, c0);
  return transpose(float3x3(c0, c1, c2)) / det;
}
