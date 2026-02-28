// ═══════════════════════════════════════════════════════════════════
// Globe Dots — Fibonacci-distributed points on sphere
// ──────────────────────────────────────────────────────
// Professional quality dots with:
//   • Per-dot random size variation (aSize attribute)
//   • NormalBlending — dark side alpha ~0.12 (NOT invisible)
//   • Subtle color: warm white → brand orange gradient
//   • Slightly more dots for denser, richer coverage
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";
import { dotVertexShader, dotFragmentShader } from "./shaders/dotShaders";

const PHI = (1 + Math.sqrt(5)) / 2;
const GOLDEN_ANGLE = (2 * Math.PI) / (PHI * PHI);

export interface GlobeDots {
  points: THREE.Points;
  material: THREE.ShaderMaterial;
  dispose: () => void;
}

export function createGlobeDots(isMobile: boolean): GlobeDots {
  const count = isMobile ? 1200 : 3500;
  const radius = isMobile ? 1.7 : 2.0;

  // Fibonacci sphere — even global distribution
  const positions = new Float32Array(count * 3);
  const sizes = new Float32Array(count); // per-dot random size multiplier

  // Seeded random for reproducibility
  let seed = 12345;
  const rand = () => {
    seed = (seed * 16807 + 0) % 2147483647;
    return (seed - 1) / 2147483646;
  };

  for (let i = 0; i < count; i++) {
    const y = 1 - (i / (count - 1)) * 2;
    const r = Math.sqrt(Math.max(0, 1 - y * y));
    const theta = GOLDEN_ANGLE * i;
    positions[i * 3] = Math.cos(theta) * r * radius;
    positions[i * 3 + 1] = y * radius;
    positions[i * 3 + 2] = Math.sin(theta) * r * radius;

    // Size variation: 0.4 → 1.0 with slight bias toward smaller
    sizes[i] = 0.4 + rand() * 0.6;
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute("aSize", new THREE.BufferAttribute(sizes, 1));

  const material = new THREE.ShaderMaterial({
    uniforms: {
      uLightDir: { value: new THREE.Vector3(0.7, 0.5, 1.0).normalize() },
      uTime: { value: 0 },
      uScale: { value: isMobile ? 1.5 : 2.5 },
      // Bright side: brand orange; dim side: darker/muted orange
      uColorBright: { value: new THREE.Color("#FF7A00") },
      uColorDim: { value: new THREE.Color("#B34700") },
      uMouseWorld: { value: new THREE.Vector3(999, 999, 999) },
      uMouseActive: { value: 0 },
    },
    vertexShader: dotVertexShader,
    fragmentShader: dotFragmentShader,
    transparent: true,
    depthWrite: false,
    blending: THREE.NormalBlending,
  });

  const points = new THREE.Points(geometry, material);

  const dispose = () => {
    geometry.dispose();
    material.dispose();
  };

  return { points, material, dispose };
}
