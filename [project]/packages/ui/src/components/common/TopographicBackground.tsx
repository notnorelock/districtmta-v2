import { type Component, createEffect, on, onCleanup, onMount } from "solid-js";
import * as THREE from "three";

/**
 * Seamless, slowly-morphing topographic contour-line pattern - a
 * fullscreen shader (not a particle system like SmokeBackground.tsx),
 * rendered as a single plane covering the viewport with an orthographic
 * camera. The "elevation" field is layered simplex-style noise animated
 * over time (domain warp + slow z-drift through the noise volume, see
 * the fragment shader below), banded into contour lines by taking the
 * fractional part of the elevation and thresholding near-zero into a
 * thin line - the same technique a topographic/isoline map shader uses,
 * just driven by noise instead of real heightmap data.
 *
 * Covers its container edge-to-edge at a uniform faint opacity by
 * default (an even wash of thin white contour lines across the whole
 * surface, matching the reference) - pass centerFade to fade lines out
 * toward the middle instead, for a caller layering centered foreground
 * content on top. Sits BEHIND both the login screen's
 * SmokeBackground+LoginCamera and the dashboard's content pane (see
 * AuthCard.tsx / DashboardView.tsx for how each layers it) - it's meant
 * to read as a faint ambient texture on a dark surface, not a
 * foreground effect.
 */
export interface TopographicBackgroundProps {
  /** Contour line color. Defaults to white, matching the reference (a faint white topo texture on a dark surface). */
  color?: string;
  /** Base opacity of the contour lines themselves (the field between lines stays fully transparent regardless). */
  opacity?: number;
  /** How many contour bands fit across the viewport's shorter axis - higher = denser lines. */
  density?: number;
  /** How fast the pattern drifts/morphs. 0 freezes it entirely. */
  speed?: number;
  /** Fades the contour lines out toward the center of the surface (an even wash everywhere by default - see the fragment shader's own comment). Useful when foreground content sits centered on top of this background and the lines would otherwise compete with it there. */
  centerFade?: boolean;
  class?: string;
}

const DEFAULTS: Required<Omit<TopographicBackgroundProps, "class">> = {
  color: "#ffffff",
  opacity: 0.16,
  density: 3.5,
  speed: 0.012,
  centerFade: false,
};

const VERTEX_SHADER = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = vec4(position.xy, 0.0, 1.0);
  }
`;

// Standard Ashima/webgl-noise 3D simplex noise - public domain, ported
// countless times, chosen here (over a 2D noise call twice-offset) so
// the "domain warp" below can drift the sampling point through a full
// 3D volume over time without ever visibly looping or tiling within a
// single session's runtime.
const FRAGMENT_SHADER = /* glsl */ `
  precision highp float;

  varying vec2 vUv;

  uniform vec2 uResolution;
  uniform float uTime;
  uniform vec3 uColor;
  uniform float uOpacity;
  uniform float uDensity;
  uniform float uCenterFade;

  vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
  vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

  float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;

    i = mod289(i);
    vec4 p = permute(permute(permute(
      i.z + vec4(0.0, i1.z, i2.z, 1.0))
      + i.y + vec4(0.0, i1.y, i2.y, 1.0))
      + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);

    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);

    vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
  }

  float elevationField(vec2 st, float time) {
    vec3 p1 = vec3(st, time * 0.25);
    vec3 p2 = vec3(st * 1.8 + 4.7, time * 0.25 + 30.0);
    return snoise(p1) * 0.7 + snoise(p2) * 0.3;
  }

  void main() {
    vec2 uv = vUv;
    vec2 st = (uv - 0.5) * vec2(uResolution.x / uResolution.y, 1.0) * uDensity;

    float elevation = elevationField(st, uTime);

    float bands = 7.0;
    float field = elevation * bands;
    float line = abs(fract(field) - 0.5) * 2.0;
    float width = fwidth(field) * 1.5 + 0.025;
    float contour = 1.0 - smoothstep(0.0, width, line);

    float centerDistance = length(uv - 0.5);
    float centerFadeAmount = mix(1.0, smoothstep(0.1, 0.5, centerDistance), uCenterFade);

    float alpha = contour * uOpacity * centerFadeAmount;
    gl_FragColor = vec4(uColor, alpha);
  }
`;

export const TopographicBackground: Component<TopographicBackgroundProps> = (rawProps) => {
  const props = { ...DEFAULTS, ...rawProps };

  let containerRef: HTMLDivElement | undefined;
  let scene: THREE.Scene;
  let camera: THREE.OrthographicCamera;
  let renderer: THREE.WebGLRenderer;
  let material: THREE.ShaderMaterial;
  let mesh: THREE.Mesh;
  let animationId: number;
  let resizeObserver: ResizeObserver | undefined;
  let clock: THREE.Clock;

  const initScene = () => {
    if (!containerRef) return;

    scene = new THREE.Scene();
    camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    clock = new THREE.Clock();

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(containerRef.clientWidth, containerRef.clientHeight, false);
    containerRef.appendChild(renderer.domElement);

    material = new THREE.ShaderMaterial({
      vertexShader: VERTEX_SHADER,
      fragmentShader: FRAGMENT_SHADER,
      transparent: true,
      depthTest: false,
      depthWrite: false,
      uniforms: {
        uResolution: { value: new THREE.Vector2(containerRef.clientWidth, containerRef.clientHeight) },
        uTime: { value: 0 },
        uColor: { value: new THREE.Color(props.color) },
        uOpacity: { value: props.opacity },
        uDensity: { value: props.density },
        uCenterFade: { value: props.centerFade ? 1 : 0 },
      },
    });

    const geometry = new THREE.PlaneGeometry(2, 2);
    mesh = new THREE.Mesh(geometry, material);
    scene.add(mesh);

    animate();
  };

  const animate = () => {
    animationId = requestAnimationFrame(animate);
    material.uniforms.uTime!.value += clock.getDelta() * props.speed * 30;
    renderer.render(scene, camera);
  };

  const handleResize = () => {
    if (!containerRef) return;
    renderer.setSize(containerRef.clientWidth, containerRef.clientHeight, false);
    material.uniforms.uResolution!.value.set(containerRef.clientWidth, containerRef.clientHeight);
  };

  const cleanup = () => {
    if (animationId) cancelAnimationFrame(animationId);

    mesh?.geometry.dispose();
    material?.dispose();

    if (renderer) {
      renderer.dispose();
      if (containerRef && renderer.domElement) {
        containerRef.removeChild(renderer.domElement);
      }
    }

    window.removeEventListener("resize", handleResize);
    resizeObserver?.disconnect();
  };

  createEffect(
    on(
      () => props.color,
      (newColor) => {
        material?.uniforms.uColor!.value.set(new THREE.Color(newColor));
      },
      { defer: true },
    ),
  );

  createEffect(
    on(
      () => props.opacity,
      (newOpacity) => {
        if (material) material.uniforms.uOpacity!.value = newOpacity;
      },
      { defer: true },
    ),
  );

  createEffect(
    on(
      () => props.centerFade,
      (newCenterFade) => {
        if (material) material.uniforms.uCenterFade!.value = newCenterFade ? 1 : 0;
      },
      { defer: true },
    ),
  );

  onMount(() => {
    initScene();
    window.addEventListener("resize", handleResize);

    if (containerRef) {
      resizeObserver = new ResizeObserver(handleResize);
      resizeObserver.observe(containerRef);
    }
  });

  onCleanup(cleanup);

  return (
    <div
      ref={containerRef}
      class={`pointer-events-none absolute inset-0 h-full w-full [&>canvas]:block [&>canvas]:h-full [&>canvas]:w-full ${rawProps.class ?? ""}`}
    />
  );
};
