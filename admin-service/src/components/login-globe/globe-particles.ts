// ═══════════════════════════════════════════════════════════════════
// Globe Particles — 4-pointed sparkle stars around the globe
// ────────────────────────────────────────────────────────────
// Fragment shader draws a crisp 4-point star (sparkle/diamond) SDF.
// Much lighter & sharper than the old blurry blob approach.
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";

const particleVertexShader = /* glsl */ `
attribute float aOpacity;
attribute float aSize;
varying float vOpacity;

void main() {
  vOpacity = aOpacity;
  vec4 mvPos = modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = aSize * (200.0 / -mvPos.z);
  gl_Position = projectionMatrix * mvPos;
}
`;

const particleFragmentShader = /* glsl */ `
uniform vec3  uColor;
uniform float uGlobalOpacity;
varying float vOpacity;

// 4-pointed star SDF:
// The star is the union of two thin rhombuses rotated 45° apart.
float starSDF(vec2 p, float r, float sharpness) {
  vec2 q = abs(p);
  // First lobe: vertical/horizontal
  float lobe1 = (q.x + q.y) / r;          // diamond: |x|+|y| <= r
  // Second lobe: diagonal (rotated 45°)
  vec2 d = abs(p * 0.707 + vec2(-p.y, p.x) * 0.707);
  float lobe2 = (d.x + d.y) / (r * sharpness);
  return min(lobe1, lobe2);
}

void main() {
  vec2 p = (gl_PointCoord - 0.5) * 2.0; // [-1, 1]
  float sdf = starSDF(p, 1.0, 0.38);
  if (sdf > 1.0) discard;

  // Crisp bright core + gentle halo fade
  float core  = smoothstep(1.0, 0.0, sdf);
  float inner = smoothstep(0.35, 0.0, sdf); // extra brightness at center
  float alpha = (core * 0.7 + inner * 0.5) * vOpacity * uGlobalOpacity;

  // Color: white inner core fading to brand orange at edges
  vec3 col = mix(uColor, vec3(1.0, 0.97, 0.88), inner * 0.8);

  gl_FragColor = vec4(col, clamp(alpha, 0.0, 1.0));
}
`;

export interface GlobeParticles {
  points: THREE.Points;
  material: THREE.ShaderMaterial;
  opacities: Float32Array;
  dispose: () => void;
}

export function createGlobeParticles(isMobile: boolean): GlobeParticles {
  const count = isMobile ? 18 : 40;
  const positions = new Float32Array(count * 3);
  const opacities = new Float32Array(count);
  const sizes     = new Float32Array(count);

  for (let i = 0; i < count; i++) {
    // Scatter in a shell around the globe — keep fairly close
    const r = 2.6 + Math.random() * 3.0;
    const theta = Math.random() * Math.PI * 2;
    const phi = Math.acos(2 * Math.random() - 1);
    positions[i * 3]     = r * Math.sin(phi) * Math.cos(theta);
    positions[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
    positions[i * 3 + 2] = r * Math.cos(phi);
    opacities[i] = 0.55 + Math.random() * 0.45; // bright individual sparkles
    sizes[i]     = 1.5  + Math.random() * 2.0;  // small & varied
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute("aOpacity", new THREE.BufferAttribute(opacities, 1));
  geometry.setAttribute("aSize",    new THREE.BufferAttribute(sizes,    1));

  const material = new THREE.ShaderMaterial({
    uniforms: {
      uColor: { value: new THREE.Color("#FF7A00") }, // darker orange for light bg
      uGlobalOpacity: { value: 1.0 },
    },
    vertexShader: particleVertexShader,
    fragmentShader: particleFragmentShader,
    transparent: true,
    depthWrite: false,
    blending: THREE.NormalBlending, // Using NormalBlending instead of Additive for bright backgrounds
  });

  const points = new THREE.Points(geometry, material);

  const dispose = () => {
    geometry.dispose();
    material.dispose();
  };

  return { points, material, opacities, dispose };
}

/** Drift + twinkle sparkles each frame */
export function updateParticles(particles: GlobeParticles, time: number) {
  const positions = particles.points.geometry.attributes
    .position as THREE.BufferAttribute;
  const opAttr = particles.points.geometry.attributes
    .aOpacity as THREE.BufferAttribute;
  const arr = positions.array as Float32Array;
  const opArr = opAttr.array as Float32Array;
  const count = arr.length / 3;

  for (let i = 0; i < count; i++) {
    const offset = i * 7.13;
    // Gentle drift
    arr[i * 3]     += Math.sin(time * 0.18 + offset) * 0.0003;
    arr[i * 3 + 1] += Math.cos(time * 0.13 + offset) * 0.0003;
    arr[i * 3 + 2] += Math.sin(time * 0.16 + offset * 0.7) * 0.0003;
    // Twinkle: each sparkle pulses independently
    opArr[i] = 0.55 + 0.45 * Math.abs(Math.sin(time * (0.8 + (i % 5) * 0.3) + offset));
  }
  positions.needsUpdate = true;
  opAttr.needsUpdate = true;

  particles.material.uniforms.uGlobalOpacity.value = 1.0;
}
