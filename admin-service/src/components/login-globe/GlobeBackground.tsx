import { useEffect, useRef } from "react";
import gsap from "gsap";
import { createGlobeScene } from "./globe-scene";
import { createGlobeShell } from "./globe-shell";
import { createGlobeDots } from "./globe-dots";
import { createGlobeAtmosphere } from "./globe-atmosphere";
import { createGlobeArcs } from "./globe-arcs";
import { createGlobeInteraction } from "./globe-interaction";

/** Globe auto-rotation speed in radians per second */
const AUTO_ROTATE_RAD_S = 0.06;

/** Arc dash travel speed: full arc traversal in seconds */
const ARC_CYCLE_S = 6.0;

export default function GlobeBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const isMobile = window.innerWidth < 768;

    // ── Build scene ──────────────────────────────────────────────────
    const scene      = createGlobeScene(canvas);
    const shell      = createGlobeShell(isMobile);
    const dots       = createGlobeDots(isMobile);
    const atmo       = createGlobeAtmosphere(isMobile);
    const arcs       = createGlobeArcs(isMobile);

    // Add shell FIRST (renders behind), then dots on top
    scene.globeGroup.add(shell.mesh);
    scene.globeGroup.add(dots.points);
    scene.globeGroup.add(atmo.mesh);
    scene.globeGroup.add(arcs.group);

    // Initial tilt — shows globe at an interesting angle
    scene.globeGroup.rotation.x = 0.15;
    scene.globeGroup.rotation.z = -0.08;

    // ── Interaction ───────────────────────────────────────────────────
    const interaction = createGlobeInteraction(
      canvas,
      scene.camera,
      scene.globeGroup,
      dots.material
    );

    // ── Resize ────────────────────────────────────────────────────────
    const onResize = () => {
      scene.onResize();
      atmo.material.uniforms.cameraPosition.value.copy(scene.camera.position);
    };
    window.addEventListener("resize", onResize);

    // Set initial camera position uniform
    atmo.material.uniforms.cameraPosition.value.copy(scene.camera.position);

    // ── GSAP card entrance ────────────────────────────────────────────
    const loginCard = document.querySelector<HTMLElement>(".login-card");
    if (loginCard) {
      gsap.fromTo(
        loginCard,
        { opacity: 0, y: 40, scale: 0.97 },
        {
          opacity: 1,
          y: 0,
          scale: 1,
          duration: 1.0,
          delay: 0.3,
          ease: "power3.out",
        }
      );
    }

    // ── Animation loop ────────────────────────────────────────────────
    let rafId: number;
    let prevTime = 0;

    const animate = (now: number) => {
      rafId = requestAnimationFrame(animate);
      const elapsed = scene.clock.getElapsedTime();
      const delta = Math.min((now - prevTime) / 1000, 0.05);
      prevTime = now;

      // Auto-rotate
      scene.globeGroup.rotation.y += AUTO_ROTATE_RAD_S * delta;

      // Dot uniforms
      dots.material.uniforms.uTime.value = elapsed;

      // Shell time uniform
      shell.material.uniforms.uTime.value = elapsed;

      // Atmosphere
      atmo.material.uniforms.uTime.value = elapsed;
      atmo.material.uniforms.cameraPosition.value.copy(scene.camera.position);

      // Arcs
      const progresses: number[] = [];
      arcs.materials.forEach((mat, i) => {
        const speed = 1.0 / (ARC_CYCLE_S + i * 2);
        mat.uniforms.uProgress.value =
          (mat.uniforms.uProgress.value + delta * speed) % 1.0;
        progresses.push(mat.uniforms.uProgress.value);
      });
      arcs.updateHeads(progresses);

      // Interaction
      interaction.update();

      scene.renderer.render(scene.scene, scene.camera);
    };

    rafId = requestAnimationFrame(animate);

    // ── Cleanup ───────────────────────────────────────────────────────
    return () => {
      cancelAnimationFrame(rafId);
      window.removeEventListener("resize", onResize);
      interaction.dispose();
      shell.dispose();
      dots.dispose();
      atmo.dispose();
      arcs.dispose();
      scene.dispose();
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      style={{
        position: "fixed",
        top: 0,
        left: 0,
        width: "100%",
        height: "100%",
        zIndex: 0,
        pointerEvents: "none",
      }}
    />
  );
}
