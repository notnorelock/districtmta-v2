import { type Component, type JSX, Show, createMemo } from "solid-js";
import { cn } from "@/lib/cn";

interface HudIconProps {
  /** 0-100 */
  value: number;
  /** Ring color when filled - a CSS color value */
  color: string;
  /** Icon glyph, rendered centered inside the ring */
  icon: JSX.Element;
  /** Renders a static, unfilled ring instead of tracking `value` (voice placeholder) */
  static?: boolean;
  /** value <= this pulses a glow in `color` around the icon - default 10, pass 0 to disable */
  criticalThreshold?: number;
  class?: string;
}

const SIZE = 44;
const STROKE = 3;
const RADIUS_CORNER = 12;
const INSET = STROKE / 2;
const DEFAULT_CRITICAL_THRESHOLD = 10;

/**
 * A rounded-square icon whose own border doubles as a progress ring -
 * two stacked <rect> outlines (a dim full track, a bright one clipped to
 * `value`%) instead of the usual circular donut-chart ring, since the
 * icon itself is a rounded square, not a circle. `pathLength={100}` lets
 * stroke-dasharray/-dashoffset work directly in percent regardless of the
 * rect's real perimeter.
 */
export const HudIcon: Component<HudIconProps> = (props) => {
  const clamped = () => Math.max(0, Math.min(100, props.value));
  const threshold = () => props.criticalThreshold ?? DEFAULT_CRITICAL_THRESHOLD;
  // createMemo (not a plain getter) so this only re-evaluates to a NEW
  // boolean when the critical state actually flips, not on every health
  // tick - a plain () => ... getter re-runs class={cn(...)} on every
  // single value change (health is pushed every frame), which reassigns
  // className every time and restarts the CSS animation from 0%, making
  // the glow flicker/reset instead of pulsing smoothly.
  const isCritical = createMemo(() => !props.static && threshold() > 0 && clamped() <= threshold());

  return (
    <div
      class={cn("relative flex items-center justify-center rounded-xl", isCritical() && "hud-icon--critical", props.class)}
      style={{ width: `${SIZE}px`, height: `${SIZE}px`, "--glow-color": props.color }}
    >
      {/* Solid dark chip so the icon reads as UI instead of a hole showing
          the game world through it - NOT .auth-panel__glow: that class's
          `background: radial-gradient(...)` is a shorthand that fully
          overrides background-color, making the middle transparent again
          everywhere outside the two small gradient blobs (found live -
          the icon looked exactly like a bare colored ring with nothing
          behind it). Plain bg-popover keeps a solid fill and already
          matches the app's dark/violet palette (see styles/globals.css). */}
      <div class="absolute inset-0 rounded-xl bg-popover" />
      <svg width={SIZE} height={SIZE} class="absolute inset-0 -rotate-90">
        <rect
          x={INSET}
          y={INSET}
          width={SIZE - STROKE}
          height={SIZE - STROKE}
          rx={RADIUS_CORNER}
          fill="none"
          stroke="rgba(255,255,255,0.12)"
          stroke-width={STROKE}
        />
        <Show when={!props.static}>
          {/* stroke-linecap MUST stay "butt", not "round" - at/near 100%
              the arc's start and end land on the same point, and "round"
              draws an overlapping cap blob right there (looked like a
              stray colored fragment in one corner at full health). */}
          <rect
            x={INSET}
            y={INSET}
            width={SIZE - STROKE}
            height={SIZE - STROKE}
            rx={RADIUS_CORNER}
            fill="none"
            stroke={props.color}
            stroke-width={STROKE}
            stroke-linecap="butt"
            pathLength={100}
            stroke-dasharray="100"
            stroke-dashoffset={100 - clamped()}
            class="transition-[stroke-dashoffset] duration-300 ease-out"
          />
        </Show>
      </svg>
      <div class="relative flex h-[26px] w-[26px] items-center justify-center text-foreground" style={{ color: props.static ? "rgba(255,255,255,0.4)" : undefined }}>
        {props.icon}
      </div>
    </div>
  );
};
