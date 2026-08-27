import type { Component } from "solid-js";

/**
 * Static film-grain texture overlay - ported from the "Project Pillow"
 * landing-page reference's own .grain (an inline SVG feTurbulence
 * data-URI at low opacity). Purely decorative, no JS/animation - a
 * single fixed-opacity background-image, so it costs nothing at
 * runtime beyond the one-time paint. Scoped per-caller (mounted inside
 * AuthCard.tsx and DashboardView.tsx's own roots, NOT globally in
 * App.tsx like Watermark) since it's only meant to texture the login
 * and dashboard screens, not the HUD during actual gameplay.
 *
 * z-[5] - deliberately between the background layers (z-0, e.g.
 * TopographicBackground/SmokeBackground) and each caller's own
 * foreground content (z-10), so the grain textures the background
 * without ever dimming/graining the actual UI on top of it.
 */
export const GrainOverlay: Component<{ class?: string }> = (props) => {
  return (
    <div
      aria-hidden="true"
      class={`pointer-events-none absolute inset-0 z-5 opacity-[0.035] ${props.class ?? ""}`}
      style={{
        "background-image":
          "url(\"data:image/svg+xml,%3Csvg viewBox='0 0 160 160' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.8'/%3E%3C/svg%3E\")",
      }}
    />
  );
};
