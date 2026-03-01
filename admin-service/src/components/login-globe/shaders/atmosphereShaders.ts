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
// Wider warm rim glow. pow(2.0) = broader falloff.
// Clamped to 0.75 max alpha to keep it visible but smooth.
// ═══════════════════════════════════════════════════════════════════
export const atmosphereFragmentShader = /* glsl */ `
uniform vec3  uGlowColor;
uniform float uGlowIntensity;
uniform float uTime;
// NOTE: cameraPosition is a Three.js built-in uniform — do NOT redeclare it.

varying vec3 vWorldNormal;
varying vec3 vWorldPos;

void main() {
  vec3 viewDir  = normalize(cameraPosition - vWorldPos);
  float rim     = abs(dot(viewDir, normalize(vWorldNormal)));
  float fresnel = pow(1.0 - rim, 2.0);

  float pulse = 0.95 + sin(uTime * 0.3) * 0.05;
  float alpha = fresnel * uGlowIntensity * pulse;
  alpha = clamp(alpha, 0.0, 0.75);

  vec3 color = mix(uGlowColor * 0.6, uGlowColor, fresnel);
  gl_FragColor = vec4(color, alpha);
}
`;

