// ═══════════════════════════════════════════════════════════════════
// Globe Atmosphere — Subtle rim glow halo
// ────────────────────────────────────────
// Thinner and more refined than before:
//   • 1.12x radius (was 1.18x — less spread)
//   • Lower intensity (0.55 vs 0.85)
//   • AdditiveBlending for natural glow
//   • Warmer, less saturated orange
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";
import {
  atmosphereVertexShader,
  atmosphereFragmentShader,
} from "./shaders/atmosphereShaders";

export interface GlobeAtmosphere {
  mesh: THREE.Mesh;
  material: THREE.ShaderMaterial;
  dispose: () => void;
}

export function createGlobeAtmosphere(isMobile: boolean): GlobeAtmosphere {
  const globeRadius = isMobile ? 1.7 : 2.0;
  const atmRadius = globeRadius * 1.12; // tighter fit

  const geometry = new THREE.SphereGeometry(atmRadius, 64, 64);

  const material = new THREE.ShaderMaterial({
    uniforms: {
      uGlowColor: { value: new THREE.Color("#FF7030") },
      uGlowIntensity: { value: 0.55 },
      uTime: { value: 0 },
      cameraPosition: { value: new THREE.Vector3() },
    },
    vertexShader: atmosphereVertexShader,
    fragmentShader: atmosphereFragmentShader,
    transparent: true,
    depthWrite: false,
    side: THREE.BackSide,
    blending: THREE.AdditiveBlending,
  });

  const mesh = new THREE.Mesh(geometry, material);

  const dispose = () => {
    geometry.dispose();
    material.dispose();
  };

  return { mesh, material, dispose };
}
