// ═══════════════════════════════════════════════════════════════════
// Globe Arcs — Elegant connection lines between cities
// ─────────────────────────────────────────────────────
// Key improvements:
//   • Thinner tubes (0.004 radius vs 0.007)
//   • NormalBlending to avoid glow-blob appearance
//   • All-hemisphere distribution (not just upper)
//   • Fewer arcs for cleaner look
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";
import { arcVertexShader, arcFragmentShader } from "./shaders/arcShaders";

export interface GlobeArcs {
  group: THREE.Group;
  materials: THREE.ShaderMaterial[];
  dispose: () => void;
}

/** Seeded pseudo-random for reproducible arcs */
function seededRng(seed: number) {
  let s = seed;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

/** Random point on unit sphere (Marsaglia) */
function randomOnSphere(rng: () => number): THREE.Vector3 {
  let x: number, y: number, s: number;
  do {
    x = rng() * 2 - 1;
    y = rng() * 2 - 1;
    s = x * x + y * y;
  } while (s >= 1);
  const f = 2 * Math.sqrt(1 - s);
  return new THREE.Vector3(x * f, y * f, 2 * s - 1);
}

function buildArc(
  p1: THREE.Vector3,
  p2: THREE.Vector3,
  radius: number
): THREE.CubicBezierCurve3 {
  const a = p1.clone().multiplyScalar(radius);
  const b = p2.clone().multiplyScalar(radius);

  const mid = p1.clone().add(p2).normalize();
  const cordalDist = p1.distanceTo(p2);
  const liftFactor = 0.25 + cordalDist * 0.25;
  const lift = radius * (1.0 + liftFactor);

  const midPt = mid.clone().multiplyScalar(lift);
  const cp1 = a.clone().lerp(midPt, 0.45);
  const cp2 = b.clone().lerp(midPt, 0.45);

  return new THREE.CubicBezierCurve3(a, cp1, cp2, b);
}

export function createGlobeArcs(isMobile: boolean): GlobeArcs {
  const arcCount = isMobile ? 4 : 7;
  const radius = isMobile ? 1.7 : 2.0;
  const group = new THREE.Group();
  const materials: THREE.ShaderMaterial[] = [];
  const geometries: THREE.BufferGeometry[] = [];

  const rng = seededRng(42);

  for (let i = 0; i < arcCount; i++) {
    let p1: THREE.Vector3, p2: THREE.Vector3;
    let attempts = 0;
    do {
      p1 = randomOnSphere(rng).normalize();
      p2 = randomOnSphere(rng).normalize();
      attempts++;
    } while (
      (p1.distanceTo(p2) < 0.5 || p1.distanceTo(p2) > 1.6) &&
      attempts < 20
    );

    const curve = buildArc(p1, p2, radius);
    // Thinner tubes — 0.004 radius (was 0.007)
    const geometry = new THREE.TubeGeometry(curve, 64, 0.004, 5, false);
    geometries.push(geometry);

    const material = new THREE.ShaderMaterial({
      uniforms: {
        uProgress: { value: i / arcCount },
        uColorStart: { value: new THREE.Color("#FF6A30") },
        uColorEnd: { value: new THREE.Color("#FFD4B0") },
      },
      vertexShader: arcVertexShader,
      fragmentShader: arcFragmentShader,
      transparent: true,
      depthWrite: false,
      blending: THREE.NormalBlending,
      side: THREE.DoubleSide,
    });
    materials.push(material);

    group.add(new THREE.Mesh(geometry, material));
  }

  const dispose = () => {
    geometries.forEach((g) => g.dispose());
    materials.forEach((m) => m.dispose());
  };

  return { group, materials, dispose };
}
