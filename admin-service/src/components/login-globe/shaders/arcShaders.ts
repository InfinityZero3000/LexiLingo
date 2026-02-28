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
// - Longer dash length for more visible trails
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
  // Increase dashLen heavily for comet trail effect across the whole orbit
  const float dashLen = 0.50; 

  float d = head - pos;
  float dWrapped = head + (1.0 - pos);
  float dist = d;
  if (d < 0.0) dist = dWrapped;
  if (dist < 0.0 || dist > dashLen) discard;

  float t = 1.0 - (dist / dashLen);
  
  // Power falloff creates the "comet" look: fast fade near tail, solid at head
  float lineIntensity = pow(t, 4.0);
  
  // Bright glowing dot exactly at the head
  float headDot = smoothstep(0.015, 0.0, dist);

  // Tube cross-section logic: keep it round, pinch the tail
  float cross = sin(vUv.y * 3.14159);
  float lineCross = pow(clamp(cross, 0.0, 1.0), mix(4.0, 1.0, lineIntensity));
  float dotCross = pow(clamp(cross, 0.0, 1.0), 3.0); 

  // Color gradient from tail (deep orange) to head (white/yellow)
  vec3 color = mix(uColorStart, uColorEnd, lineIntensity);
  color = mix(color, vec3(1.0, 1.0, 1.0), headDot * dotCross); // pure white core

  float alpha = (lineIntensity * lineCross * 0.9) + (headDot * dotCross * 2.0);
  alpha = clamp(alpha, 0.0, 1.0);
  
  gl_FragColor = vec4(color, alpha);
}
`;
