import * as THREE from "three";
import gsap from "gsap";

export interface GlobeInteraction {
  update: () => void;
  dispose: () => void;
}

/**
 * Globe interaction — listens on `window` so the canvas can be
 * pointer-events:none and never block UI (Google sign-in button, etc.)
 * - Mouse/touch move → gentle parallax rotation via GSAP quickTo
 * - Raycaster → uMouseWorld for proximity dot highlight
 */
export function createGlobeInteraction(
  _canvas: HTMLCanvasElement,  // kept in signature for compatibility
  camera: THREE.PerspectiveCamera,
  globeGroup: THREE.Group,
  dotMaterial: THREE.ShaderMaterial
): GlobeInteraction {
  const mouse = new THREE.Vector2(0, 0);
  const raycaster = new THREE.Raycaster();
  // Sphere matches globeGroup position (y=-1.8) and globe radius(2.0)+margin
  const sphereHelper = new THREE.Sphere(new THREE.Vector3(0, -1.8, 0), 2.1);

  // GSAP-damped rotation — decoupled from auto-rotate so it's additive offset
  const rotOffset = { x: 0, y: 0 };
  const smoothX = gsap.quickTo(rotOffset, "x", { duration: 1.4, ease: "power2.out" });
  const smoothY = gsap.quickTo(rotOffset, "y", { duration: 1.4, ease: "power2.out" });

  // Rotation bias applied on top of auto-rotate in update()
  let mouseActive = false;
  let rotBiasX = 0;
  let rotBiasY = 0;

  const onMouseMove = (e: MouseEvent) => {
    mouse.x = (e.clientX / window.innerWidth)  * 2 - 1;
    mouse.y = -(e.clientY / window.innerHeight) * 2 + 1;
    mouseActive = true;

    // Max parallax tilt: ±0.12 rad X, ±0.22 rad Y
    const targetX = mouse.y * 0.12;
    const targetY = mouse.x * 0.22;
    smoothX(targetX);
    smoothY(targetY);
  };

  const onMouseLeave = () => {
    mouseActive = false;
    smoothX(0);
    smoothY(0);
    dotMaterial.uniforms.uMouseActive.value = 0;
    dotMaterial.uniforms.uMouseWorld.value.set(999, 999, 999);
  };

  const onTouchMove = (e: TouchEvent) => {
    if (e.touches.length !== 1) return;
    const t = e.touches[0];
    mouse.x = (t.clientX / window.innerWidth)  * 2 - 1;
    mouse.y = -(t.clientY / window.innerHeight) * 2 + 1;
    mouseActive = true;
    smoothX(mouse.y * 0.08);
    smoothY(mouse.x * 0.14);
  };

  const onTouchEnd = () => {
    mouseActive = false;
    smoothX(0);
    smoothY(0);
    dotMaterial.uniforms.uMouseActive.value = 0;
    dotMaterial.uniforms.uMouseWorld.value.set(999, 999, 999);
  };

  // Listen on window — canvas stays pointer-events:none
  window.addEventListener("mousemove", onMouseMove);
  window.addEventListener("mouseleave", onMouseLeave);
  window.addEventListener("touchmove", onTouchMove, { passive: true });
  window.addEventListener("touchend", onTouchEnd);

  const ray = new THREE.Ray();

  const update = () => {
    // Apply parallax bias smoothly on top of the auto-rotation in RAF
    globeGroup.rotation.x += (rotOffset.x - rotBiasX) * 0.08;
    globeGroup.rotation.y += (rotOffset.y - rotBiasY) * 0.08;
    rotBiasX += (rotOffset.x - rotBiasX) * 0.08;
    rotBiasY += (rotOffset.y - rotBiasY) * 0.08;

    if (!mouseActive) {
      dotMaterial.uniforms.uMouseActive.value = 0;
      return;
    }

    // Raycast for proximity highlight
    raycaster.setFromCamera(mouse, camera);
    ray.copy(raycaster.ray);

    const hit = new THREE.Vector3();
    if (ray.intersectSphere(sphereHelper, hit)) {
      const local = hit.clone().sub(globeGroup.position);
      dotMaterial.uniforms.uMouseWorld.value.copy(local);
      dotMaterial.uniforms.uMouseActive.value = 1;
    } else {
      dotMaterial.uniforms.uMouseActive.value = 0;
      dotMaterial.uniforms.uMouseWorld.value.set(999, 999, 999);
    }
  };

  const dispose = () => {
    window.removeEventListener("mousemove", onMouseMove);
    window.removeEventListener("mouseleave", onMouseLeave);
    window.removeEventListener("touchmove", onTouchMove);
    window.removeEventListener("touchend", onTouchEnd);
  };

  return { update, dispose };
}
