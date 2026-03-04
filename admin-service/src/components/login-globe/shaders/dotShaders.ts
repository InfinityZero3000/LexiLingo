// ═══════════════════════════════════════════════════════════════════
// Dot Vertex Shader
// ─────────────────
// Professional globe dots inspired by Italgas HYROUND / BlueOrbit:
//   • Hemispheric lighting with SOFT terminator (no hard cutoff)
//   • Dark side still visible at low alpha (~0.12) for shape continuity
//   • Per-dot size randomness via hash for organic feel
//   • Limb fade: dots at sphere edge are smaller (depth perspective)
// ═══════════════════════════════════════════════════════════════════
export const dotVertexShader = /* glsl */ `
uniform vec3  uLightDir;
uniform float uTime;
uniform float uScale;
uniform vec3  uMouseWorld;
uniform float uMouseActive;

attribute float aSize;      // per-dot random size multiplier [0.4 .. 1.0]

varying float vBrightness;
varying float vMouseProx;

void main() {
  vec3 normal = normalize(position);

  // ── Lighting ───────────────────────────────────
  // Soft hemispheric: bright side → terminator → dark side
  // Using smoothstep for gentle roll-off (NOT pow cutoff)
  float NdL = dot(normal, normalize(uLightDir));
  //  -1 (back) → +1 (front)
  //  Remap to 0..1 with soft wrap-around lighting
  float brightness = smoothstep(-0.6, 0.85, NdL);

  // Very subtle per-dot breathing
  float breathe = sin(uTime * 0.35 + normal.x * 4.1 + normal.z * 3.3) * 0.03;
  brightness = clamp(brightness + breathe, 0.0, 1.0);
  vBrightness = brightness;

  // ── Mouse proximity ────────────────────────────
  float mDist = distance(position, uMouseWorld);
  vMouseProx = smoothstep(0.5, 0.0, mDist) * uMouseActive;

  // ── Position in camera space ───────────────────
  vec4 mvPos = modelViewMatrix * vec4(position, 1.0);

  // ── Size ───────────────────────────────────────
  // Base from lighting: narrow range so large dots spread more evenly
  // aSize attribute adds per-dot variation
  float sizeBase = mix(7.5, 10.0, brightness) * aSize;
  sizeBase += vMouseProx * 2.0;
  gl_PointSize = sizeBase * uScale;

  gl_Position = projectionMatrix * mvPos;
}
`;

// ═══════════════════════════════════════════════════════════════════
// Dot Fragment Shader
// ─────────────────
// Smooth circle with anti-aliased edge.
// Dark side: still visible (~0.12 alpha) to maintain sphere shape.
// Color gradient: lit side warm white → dim side brand orange.
// ═══════════════════════════════════════════════════════════════════
export const dotFragmentShader = /* glsl */ `
uniform vec3 uColorBright;   // warm white
uniform vec3 uColorDim;      // brand orange

varying float vBrightness;
varying float vMouseProx;

void main() {
  // Circle SDF with smooth anti-aliased edge
  vec2 p = gl_PointCoord - vec2(0.5);
  float d = length(p) * 2.0;
  if (d > 1.0) discard;

  float edge = smoothstep(1.0, 0.4, d);

  // ── Alpha ──────────────────────────────────────
  // Dark side: alpha = 0.12 * edge (visible but very muted)
  // Bright side: alpha = 0.9 * edge
  float alpha = mix(0.12, 0.9, vBrightness) * edge;

  // Mouse proximity boost
  alpha = max(alpha, vMouseProx * edge * 0.75);
  alpha = clamp(alpha, 0.0, 1.0);

  // ── Color ──────────────────────────────────────
  vec3 color = mix(uColorDim, uColorBright, vBrightness);
  color = mix(color, vec3(1.0), vMouseProx * 0.6);

  gl_FragColor = vec4(color, alpha);
}
`;

