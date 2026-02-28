// ═══════════════════════════════════════════════════════════════════
// Arc Vertex Shader — pass UV for animated traveling light
// ═══════════════════════════════════════════════════════════════════
export const arcVertexShader = /* glsl */ `
varying vec2 vUv;

void main() {
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

// ═══════════════════════════════════════════════════════════════════
// Arc Fragment Shader
// ───────────────────
// Thin, elegant connection lines with a traveling bright pulse.
// - Shorter dash length (0.12) for sleeker look
// - Softer tube cross-section
// - Delicate color: brand orange fading to warm white
// ═══════════════════════════════════════════════════════════════════
export const arcFragmentShader = /* glsl */ `
uniform float uProgress;
uniform vec3  uColorStart;
uniform vec3  uColorEnd;

varying vec2  vUv;

void main() {
  float pos  = vUv.x;
  float head = uProgress;
  const float dashLen = 0.14;

  float d = head - pos;
  float dWrapped = head + (1.0 - pos);
  float dist = d;
  if (d < 0.0) dist = dWrapped;
  if (dist < 0.0 || dist > dashLen) discard;

  float t = 1.0 - (dist / dashLen);
  float intensity = t * t * t;         // cubic falloff — sharper head

  // Tube cross-section: thinner center stripe
  float cross = sin(vUv.y * 3.14159);
  cross = pow(clamp(cross, 0.0, 1.0), 1.5);

  vec3 color = mix(uColorStart, uColorEnd, t);
  color = mix(color, vec3(1.0), intensity * 0.6);

  float alpha = intensity * cross * 0.7;
  gl_FragColor = vec4(color, alpha);
}
`;
