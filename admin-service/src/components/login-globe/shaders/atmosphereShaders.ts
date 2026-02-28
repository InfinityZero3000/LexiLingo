// ═══════════════════════════════════════════════════════════════════
// Atmosphere Vertex Shader
// ────────────────────────
// BackSide Fresnel rim glow – thin halo around globe perimeter.
// World-space computation for correct Fresnel regardless of rotation.
// ═══════════════════════════════════════════════════════════════════
export const atmosphereVertexShader = /* glsl */ `
varying vec3 vWorldNormal;
varying vec3 vWorldPos;

void main() {
  vWorldNormal = normalize((modelMatrix * vec4(normal, 0.0)).xyz);
  vec4 worldPos4 = modelMatrix * vec4(position, 1.0);
  vWorldPos = worldPos4.xyz;
  gl_Position = projectionMatrix * viewMatrix * worldPos4;
}
`;

// ═══════════════════════════════════════════════════════════════════
// Atmosphere Fragment Shader
// ─────────────────────────
// Thin warm rim glow.  pow(3.5) = sharper/thinner than before.
// Clamped to 0.45 max alpha so it never overpowers the dots.
// ═══════════════════════════════════════════════════════════════════
export const atmosphereFragmentShader = /* glsl */ `
uniform vec3  uGlowColor;
uniform float uGlowIntensity;
uniform float uTime;
uniform vec3  cameraPosition;

varying vec3 vWorldNormal;
varying vec3 vWorldPos;

void main() {
  vec3 viewDir  = normalize(cameraPosition - vWorldPos);
  float rim     = abs(dot(viewDir, normalize(vWorldNormal)));
  float fresnel = pow(1.0 - rim, 3.5);

  float pulse = 0.95 + sin(uTime * 0.3) * 0.05;
  float alpha = fresnel * uGlowIntensity * pulse;
  alpha = clamp(alpha, 0.0, 0.45);

  vec3 color = mix(uGlowColor * 0.6, uGlowColor, fresnel);
  gl_FragColor = vec4(color, alpha);
}
`;

