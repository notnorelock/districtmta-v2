import { type Component, createEffect, on, onCleanup, onMount } from "solid-js";
import * as THREE from "three";

// Ported from an earlier project's amethyst-uii (Vue 3 + three.js) smoke
// particle backdrop - see AuthCard.tsx's module comment for the rest of
// that lineage. Vue's ref/watch/onMounted/onUnmounted map onto Solid's
// signals/createEffect/onMount/onCleanup one-to-one here; the actual
// three.js particle simulation logic is unchanged.

export interface SmokeBackgroundProps {
  density?: number;
  color?: string;
  opacity?: number;
  enableRotation?: boolean;
  rotation?: [number, number, number];
  enableWind?: boolean;
  windStrength?: [number, number, number];
  windDirection?: [number, number, number];
  enableTurbulence?: boolean;
  turbulenceStrength?: [number, number, number];
  size?: [number, number, number];
  minBounds?: [number, number, number];
  maxBounds?: [number, number, number];
  maxVelocity?: [number, number, number];
  velocityResetFactor?: number;
  class?: string;
  /** Renders with a transparent WebGL context instead of an opaque black background - for layering the smoke over something other than solid black (e.g. SpawnSelectView.tsx's map). Defaults to false to keep AuthCard.tsx's own black-backed usage unchanged. */
  transparent?: boolean;
}

const DEFAULTS: Required<Omit<SmokeBackgroundProps, "class">> = {
  density: 50,
  color: "#ffffff",
  opacity: 0.5,
  enableRotation: false,
  rotation: [0, 0, 0.1],
  enableWind: false,
  windStrength: [0.01, 0.01, 0.01],
  windDirection: [1, 0, 0],
  enableTurbulence: false,
  turbulenceStrength: [0.01, 0.01, 0.01],
  size: [1000, 1000, 1000],
  minBounds: [-800, -800, -800],
  maxBounds: [800, 800, 800],
  maxVelocity: [30, 30, 0],
  velocityResetFactor: 10,
  transparent: false,
};

export const SmokeBackground: Component<SmokeBackgroundProps> = (rawProps) => {
  const props = { ...DEFAULTS, ...rawProps };

  let containerRef: HTMLDivElement | undefined;
  let scene: THREE.Scene;
  let camera: THREE.PerspectiveCamera;
  let renderer: THREE.WebGLRenderer;
  let particles: THREE.Mesh[] = [];
  let animationId: number;
  let smokeTexture: THREE.Texture | undefined;

  const initScene = async () => {
    if (!containerRef) return;

    scene = new THREE.Scene();
    if (!props.transparent) {
      scene.background = new THREE.Color(0x000000);
    }

    camera = new THREE.PerspectiveCamera(60, containerRef.clientWidth / containerRef.clientHeight, 1, 6000);
    camera.position.z = 500;

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: props.transparent });
    renderer.setSize(containerRef.clientWidth, containerRef.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    containerRef.appendChild(renderer.domElement);

    const textureLoader = new THREE.TextureLoader();
    smokeTexture = await textureLoader.loadAsync(new URL("@/assets/textures/smoke.png", import.meta.url).href);

    const geometry = new THREE.PlaneGeometry(props.size[0], props.size[1]);

    const material = new THREE.MeshLambertMaterial({
      map: smokeTexture,
      transparent: true,
      opacity: props.opacity,
      depthWrite: false,
      color: new THREE.Color(props.color),
      polygonOffset: true,
      polygonOffsetFactor: 1,
      polygonOffsetUnits: 1,
    });

    particles = [];
    for (let i = 0; i < props.density; i++) {
      const particle = new THREE.Mesh(geometry, material.clone());

      const x = Math.random() * (props.maxBounds[0] - props.minBounds[0]) + props.minBounds[0];
      const y = Math.random() * (props.maxBounds[1] - props.minBounds[1]) + props.minBounds[1];
      const z = Math.random() * (props.maxBounds[2] - props.minBounds[2]) + props.minBounds[2];
      particle.position.set(x, y, z);

      particle.userData.velocity = new THREE.Vector3(
        Math.random() * props.maxVelocity[0] * 2 - props.maxVelocity[0],
        Math.random() * props.maxVelocity[1] * 2 - props.maxVelocity[1],
        Math.random() * props.maxVelocity[2] * 2 - props.maxVelocity[2],
      );

      if (props.enableRotation) {
        const [rx, ry, rz] = props.rotation;
        particle.rotation.set(Math.random() * rx * 2 - rx, Math.random() * ry * 2 - ry, Math.random() * rz * 2 - rz);
      }

      if (props.enableTurbulence) {
        particle.userData.turbulence = new THREE.Vector3(
          Math.random() * 2 * Math.PI,
          Math.random() * 2 * Math.PI,
          Math.random() * 2 * Math.PI,
        );
      }

      particles.push(particle);
      scene.add(particle);
    }

    const light = new THREE.DirectionalLight(0xffffff, 0.75);
    light.position.set(-1, 0, 1);
    scene.add(light);

    const ambientLight = new THREE.AmbientLight(0x555555);
    scene.add(ambientLight);

    animate();
  };

  const animate = () => {
    animationId = requestAnimationFrame(animate);

    const delta = 0.016; // ~60fps
    const tempVec3 = new THREE.Vector3();

    particles.forEach((particle) => {
      const velocity = particle.userData.velocity as THREE.Vector3;
      const turbulence = particle.userData.turbulence as THREE.Vector3 | undefined;

      if (props.enableTurbulence && turbulence) {
        tempVec3.set(
          Math.sin(turbulence.x) * turbulence.length() * props.turbulenceStrength[0],
          Math.sin(turbulence.y) * turbulence.length() * props.turbulenceStrength[1],
          Math.sin(turbulence.z) * turbulence.length() * props.turbulenceStrength[2],
        );
        velocity.add(tempVec3);
      }

      if (props.enableWind) {
        velocity.x += props.windDirection[0] * props.windStrength[0];
        velocity.y += props.windDirection[1] * props.windStrength[1];
        velocity.z += props.windDirection[2] * props.windStrength[2];
      }

      velocity.x = THREE.MathUtils.clamp(velocity.x, -props.maxVelocity[0], props.maxVelocity[0]);
      velocity.y = THREE.MathUtils.clamp(velocity.y, -props.maxVelocity[1], props.maxVelocity[1]);
      velocity.z = THREE.MathUtils.clamp(velocity.z, -props.maxVelocity[2], props.maxVelocity[2]);
      velocity.z = 0; // Disable z-axis movement

      particle.position.add(tempVec3.set(velocity.x, velocity.y, velocity.z).multiplyScalar(delta));

      if (props.enableRotation) {
        const [rx, ry, rz] = props.rotation;
        particle.rotation.x += rx * delta;
        particle.rotation.y += ry * delta;
        particle.rotation.z += rz * delta;
      }

      const [minX, minY, minZ] = props.minBounds;
      const [maxX, maxY, maxZ] = props.maxBounds;
      if (
        particle.position.x < minX ||
        particle.position.x > maxX ||
        particle.position.y < minY ||
        particle.position.y > maxY ||
        particle.position.z < minZ ||
        particle.position.z > maxZ
      ) {
        const center = tempVec3.set((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
        const targetDirection = center.sub(particle.position).normalize();
        velocity.add(targetDirection.multiplyScalar(props.velocityResetFactor));

        if (turbulence) {
          turbulence.set(Math.random() * 2 * Math.PI, Math.random() * 2 * Math.PI, Math.random() * 2 * Math.PI);
        }
      }
    });

    renderer.render(scene, camera);
  };

  const handleResize = () => {
    if (!containerRef) return;

    camera.aspect = containerRef.clientWidth / containerRef.clientHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(containerRef.clientWidth, containerRef.clientHeight);
  };

  const cleanup = () => {
    if (animationId) {
      cancelAnimationFrame(animationId);
    }

    particles.forEach((particle) => {
      particle.geometry.dispose();
      (particle.material as THREE.Material).dispose();
      scene.remove(particle);
    });
    particles = [];

    smokeTexture?.dispose();

    if (renderer) {
      renderer.dispose();
      if (containerRef && renderer.domElement) {
        containerRef.removeChild(renderer.domElement);
      }
    }

    window.removeEventListener("resize", handleResize);
  };

  createEffect(
    on(
      () => props.color,
      (newColor) => {
        particles.forEach((particle) => {
          (particle.material as THREE.MeshLambertMaterial).color = new THREE.Color(newColor);
        });
      },
      { defer: true },
    ),
  );

  createEffect(
    on(
      () => props.opacity,
      (newOpacity) => {
        particles.forEach((particle) => {
          (particle.material as THREE.MeshLambertMaterial).opacity = newOpacity;
        });
      },
      { defer: true },
    ),
  );

  onMount(() => {
    void initScene();
    window.addEventListener("resize", handleResize);
  });

  onCleanup(cleanup);

  return <div ref={containerRef} class={`pointer-events-none absolute inset-0 h-full w-full [&>canvas]:block ${rawProps.class ?? ""}`} />;
};
