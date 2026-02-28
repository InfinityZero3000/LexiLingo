// ═══════════════════════════════════════════════════════════════════
// Globe Shell — Pearlescent Base Sphere
// ──────────────────────────────────────
// A semi-translucent glossy sphere that sits UNDERNEATH the dots,
// giving the globe a visible 3D shape even on the dark side.
//
// Inspired by the BlueOrbit / HYROUND reference images where a
// subtle smooth sphere surface is clearly visible beneath the dots.
//
// Uses a custom shader for:
//   • Hemispheric lighting with soft terminator
//   • Subtle specular highlight (pearlescent sheen)
//   • Low base alpha so dots remain the hero element
//   • Slight Fresnel edge brightening (limb glow)
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";

const shellVertexShader = /* glsl */ `
uniform vec3 uLightDir;

varying float vNdL;
varying float vFresnel;
varying vec3  vNormal;
varying vec3  vViewDir;

void main() {
  vec3 n        = normalize(normalMatrix * normal);
  vec4 mvPos    = modelViewMatrix * vec4(position, 1.0);
  vec3 viewDir  = normalize(-mvPos.xyz);

  vNormal  = n;
  vViewDir = viewDir;
  vNdL     = dot(n, normalize(normalMatrix * uLightDir));

  // Fresnel: stronger at edges
  float rim = max(dot(viewDir, n), 0.0);
  vFresnel  = pow(1.0 - rim, 2.0);

  gl_Position = projectionMatrix * mvPos;
}
`;

const shellFragmentShader = /* glsl */ `
uniform vec3  uBaseColor;      // dark tint
uniform vec3  uHighlightColor; // warm specular
uniform float uOpacity;
uniform float uTime;

varying float vNdL;
varying float vFresnel;
varying vec3  vNormal;
varying vec3  vViewDir;

void main() {
  // Hemispheric light with very soft wrap
  float lit = smoothstep(-0.5, 0.9, vNdL);

  // Specular: Blinn-Phong style
  vec3 halfDir  = normalize(vViewDir + normalize(vec3(0.5, 0.6, 1.0)));
  float spec    = pow(max(dot(vNormal, halfDir), 0.0), 32.0);

  // Base color: darker on shadow side
  vec3 color = uBaseColor * (0.3 + 0.7 * lit);

  // Add warm specular highlight
  color += uHighlightColor * spec * 0.4;

  // Fresnel edge: subtle limb brightening
  color += uHighlightColor * vFresnel * 0.15;

  // Alpha: lit side more visible, dark side more transparent
  // This lets dots show through while keeping sphere shape visible
  float alpha = uOpacity * (0.4 + 0.6 * lit);

  // Very subtle breathing
  alpha *= 0.97 + sin(uTime * 0.25) * 0.03;

  gl_FragColor = vec4(color, alpha);
}
`;

export interface GlobeShell {
  mesh: THREE.Mesh;
  material: THREE.ShaderMaterial;
  dispose: () => void;
}

export function createGlobeShell(isMobile: boolean): GlobeShell {
  const radius = (isMobile ? 1.7 : 2.0) - 0.02; // slightly inside dots
  const segments = isMobile ? 48 : 64;

  const geometry = new THREE.SphereGeometry(radius, segments, segments);

  const material = new THREE.ShaderMaterial({
    uniforms: {
      uLightDir:       { value: new THREE.Vector3(0.7, 0.5, 1.0).normalize() },
      uBaseColor:      { value: new THREE.Color("#1a1e2e") },  // dark navy
      uHighlightColor: { value: new THREE.Color("#FF8040") },  // warm orange
      uOpacity:        { value: 0.22 },  // very translucent
      uTime:           { value: 0 },
    },
    vertexShader: shellVertexShader,
    fragmentShader: shellFragmentShader,
    transparent: true,
    depthWrite: false,
    side: THREE.FrontSide,
    blending: THREE.NormalBlending,
  });

  const mesh = new THREE.Mesh(geometry, material);

  const dispose = () => {
    geometry.dispose();
    material.dispose();
  };

  return { mesh, material, dispose };
}
