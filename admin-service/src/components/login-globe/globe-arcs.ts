// ═══════════════════════════════════════════════════════════════════
// Globe Arcs — Orbiting rings for shooting stars
// ─────────────────────────────────────────────────────
// Key improvements:
//   • Uses TorusGeometry wrapped around the globe as continuous orbital rings
//   • Randomly tilted orbits to look like satellites/comets
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";
import { arcVertexShader, arcFragmentShader } from "./shaders/arcShaders";

export interface GlobeArcs {
  group: THREE.Group;
  materials: THREE.ShaderMaterial[];
  updateHeads: (progresses: number[]) => void;
  dispose: () => void;
}

/** Radial-gradient canvas texture for the comet head glow */
function createGlowTexture(): THREE.CanvasTexture {
  const sz = 128;
  const canvas = document.createElement("canvas");
  canvas.width = sz;
  canvas.height = sz;
  const ctx = canvas.getContext("2d")!;
  const cx = sz / 2;
  const grd = ctx.createRadialGradient(cx, cx, 0, cx, cx, cx);
  grd.addColorStop(0.00, "rgba(255, 245, 200, 1.0)");  // bright warm white core
  grd.addColorStop(0.12, "rgba(255, 200,  80, 0.92)"); // golden yellow
  grd.addColorStop(0.28, "rgba(255, 130,  20, 0.70)"); // orange mid
  grd.addColorStop(0.50, "rgba(255,  80,   0, 0.35)"); // deep orange edge
  grd.addColorStop(0.75, "rgba(255,  50,   0, 0.10)"); // faint halo
  grd.addColorStop(1.00, "rgba(255,  30,   0, 0.00)"); // fully transparent
  ctx.fillStyle = grd;
  ctx.fillRect(0, 0, sz, sz);
  return new THREE.CanvasTexture(canvas);
}

/** Seeded pseudo-random for reproducible arcs */
function seededRng(seed: number) {
  let s = seed;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

export function createGlobeArcs(isMobile: boolean): GlobeArcs {
  const arcCount = isMobile ? 3 : 6;
  const radius = isMobile ? 1.7 : 2.0;
  const group = new THREE.Group();
  const materials: THREE.ShaderMaterial[] = [];
  const geometries: THREE.BufferGeometry[] = [];

  const rng = seededRng(42);
  const orbitRadii: number[] = [];
  const orbitMeshes: THREE.Mesh[] = [];

  for (let i = 0; i < arcCount; i++) {
    // Generate an orbital ring slightly larger than the globe
    const orbitRadius = radius * (1.05 + rng() * 0.15); 
    const tubeRadius = 0.010; // Thicker for star head
    
    // TorusGeometry acts as a continuous loop. 
    // TubularSegments should be high for smooth trails.
    const geometry = new THREE.TorusGeometry(orbitRadius, tubeRadius, 8, 180);
    geometries.push(geometry);

    const material = new THREE.ShaderMaterial({
      uniforms: {
        uProgress: { value: rng() },
        uColorStart: { value: new THREE.Color("#FF4D00") }, // Deep orange tail
        uColorEnd: { value: new THREE.Color("#FFF2C8") }, // Bright yellow/white head
      },
      vertexShader: arcVertexShader,
      fragmentShader: arcFragmentShader,
      transparent: true,
      depthWrite: false,
      blending: THREE.NormalBlending,
      side: THREE.DoubleSide,
    });
    materials.push(material);

    const mesh = new THREE.Mesh(geometry, material);
    
    // Randomize the orbit plane orientation
    mesh.rotation.x = rng() * Math.PI * 2;
    mesh.rotation.y = rng() * Math.PI * 2;
    mesh.rotation.z = rng() * Math.PI * 2;
    
    group.add(mesh);
    orbitRadii.push(orbitRadius);
    orbitMeshes.push(mesh);
  }

  // ── Head glow sprites ───────────────────────────────────────────
  const headPosArr = new Float32Array(arcCount * 3);
  const headGeo = new THREE.BufferGeometry();
  headGeo.setAttribute("position", new THREE.BufferAttribute(headPosArr, 3));

  const glowTex = createGlowTexture();
  const headMat = new THREE.PointsMaterial({
    map: glowTex,
    size: 0.55,
    sizeAttenuation: true,
    transparent: true,
    depthWrite: false,
    blending: THREE.NormalBlending,
    alphaTest: 0.01,
  });
  const headPoints = new THREE.Points(headGeo, headMat);
  group.add(headPoints);
  geometries.push(headGeo);

  const _hv = new THREE.Vector3();
  const updateHeads = (progresses: number[]) => {
    const attr = headGeo.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < arcCount; i++) {
      const angle = progresses[i] * Math.PI * 2;
      _hv.set(
        orbitRadii[i] * Math.cos(angle),
        orbitRadii[i] * Math.sin(angle),
        0
      );
      _hv.applyEuler(orbitMeshes[i].rotation);
      attr.setXYZ(i, _hv.x, _hv.y, _hv.z);
    }
    attr.needsUpdate = true;
  };

  const dispose = () => {
    geometries.forEach((g) => g.dispose());
    materials.forEach((m) => m.dispose());
    headMat.dispose();
    glowTex.dispose();
  };

  return { group, materials, updateHeads, dispose };
}
