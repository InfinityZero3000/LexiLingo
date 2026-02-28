// ═══════════════════════════════════════════════════════════════════
// Globe Particles — Floating ambient dust around globe
// ────────────────────────────────────────────────────
// Fewer, smaller, more subtle particles for a cleaner aesthetic.
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";

export interface GlobeParticles {
  points: THREE.Points;
  material: THREE.PointsMaterial;
  velocities: Float32Array;
  dispose: () => void;
}

export function createGlobeParticles(isMobile: boolean): GlobeParticles {
  const count = isMobile ? 15 : 35;
  const positions = new Float32Array(count * 3);
  const velocities = new Float32Array(count * 3);

  for (let i = 0; i < count; i++) {
    const r = 2.6 + Math.random() * 4.0;
    const theta = Math.random() * Math.PI * 2;
    const phi = Math.acos(2 * Math.random() - 1);
    positions[i * 3] = r * Math.sin(phi) * Math.cos(theta);
    positions[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
    positions[i * 3 + 2] = r * Math.cos(phi);

    velocities[i * 3] = (Math.random() - 0.5) * 0.001;
    velocities[i * 3 + 1] = (Math.random() - 0.5) * 0.001;
    velocities[i * 3 + 2] = (Math.random() - 0.5) * 0.001;
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));

  const material = new THREE.PointsMaterial({
    color: new THREE.Color("#FFA060"),
    size: isMobile ? 1.0 : 1.5,
    sizeAttenuation: true,
    transparent: true,
    opacity: 0.12,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });

  const points = new THREE.Points(geometry, material);

  const dispose = () => {
    geometry.dispose();
    material.dispose();
  };

  return { points, material, velocities, dispose };
}

/** Drift particles gently each frame */
export function updateParticles(particles: GlobeParticles, time: number) {
  const positions = particles.points.geometry.attributes
    .position as THREE.BufferAttribute;
  const arr = positions.array as Float32Array;
  const count = arr.length / 3;

  for (let i = 0; i < count; i++) {
    const offset = i * 7.13;
    arr[i * 3] += Math.sin(time * 0.3 + offset) * 0.0006;
    arr[i * 3 + 1] += Math.cos(time * 0.2 + offset) * 0.0006;
    arr[i * 3 + 2] += Math.sin(time * 0.25 + offset * 0.7) * 0.0006;
  }
  positions.needsUpdate = true;

  // Subtle opacity pulse
  particles.material.opacity = 0.10 + Math.sin(time * 0.6) * 0.03;
}
