// ═══════════════════════════════════════════════════════════════════
// Globe Scene — Camera, renderer, lighting setup
// ───────────────────────────────────────────────
// Professional framing:
//   • Globe slightly below center, top-half visible
//   • Camera pulled back for comfortable breathing room
//   • Warm directional + ambient light for shell material
//   • Alpha-clear renderer so CSS background shows through
// ═══════════════════════════════════════════════════════════════════
import * as THREE from "three";

export interface GlobeScene {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  clock: THREE.Clock;
  globeGroup: THREE.Group;
  dispose: () => void;
  onResize: () => void;
}

export function createGlobeScene(canvas: HTMLCanvasElement): GlobeScene {
  const scene = new THREE.Scene();
  const clock = new THREE.Clock();

  // ── Camera ─────────────────────────────────────────────────────
  const camera = new THREE.PerspectiveCamera(
    45,
    window.innerWidth / window.innerHeight,
    0.1,
    100
  );
  // Camera positioned to see globe center-right, slightly above equator
  camera.position.set(0, 0.3, 5.5);
  camera.lookAt(0, -0.3, 0);

  // ── Renderer ───────────────────────────────────────────────────
  const dpr = Math.min(window.devicePixelRatio, 2);
  const renderer = new THREE.WebGLRenderer({
    canvas,
    alpha: true,
    antialias: true,
    powerPreference: "high-performance",
  });
  renderer.setPixelRatio(dpr);
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setClearColor(0x000000, 0);

  // ── Globe group — moved to left ──
  const globeGroup = new THREE.Group();
  globeGroup.position.set(0, -0.3, 0);  // centered, shifted down
  scene.add(globeGroup);

  // ── Lights — for MeshStandardMaterial / shell ──────────────────
  const dirLight = new THREE.DirectionalLight(0xffe8d0, 0.6);
  dirLight.position.set(3, 4, 5);
  scene.add(dirLight);

  const ambientLight = new THREE.AmbientLight(0x404060, 0.3);
  scene.add(ambientLight);

  const onResize = () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  };

  const dispose = () => {
    renderer.dispose();
  };

  return { scene, camera, renderer, clock, globeGroup, dispose, onResize };
}
