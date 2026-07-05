public float3 calculateCameraPosition(float4x4 view) {
  float3x3 R = float3x3(view[0].xyz, view[1].xyz, view[2].xyz);
  // The CPU sends zmath row-vector matrices; through slang's column-major
  // constant-buffer lens the view translation lands in the .w components of
  // the first three logical rows — view[3].xyz is always (0,0,0).
  float3 t = float3(view[0].w, view[1].w, view[2].w);
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

public float3x3 computeTBNMatrix(float3 tangent, float3 normal) {
  // Gram-Schmidt: re-orthogonalize the interpolated tangent against the
  // interpolated normal (linear interpolation across a triangle doesn't
  // preserve perpendicularity), then derive the bitangent.
  float3 N = normalize(normal);
  // float3 T = normalize(tangent - N * dot(N, tangent));
  float3 T = normalize(tangent);
  float3 B = cross(N, T); // assumes handedness +1 — see the gap noted above

  return float3x3(T, B, N);
}
