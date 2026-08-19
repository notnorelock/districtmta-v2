import { type Component, type JSX, Show, createMemo } from "solid-js";
import styles from "./HudIcon.module.scss";

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
  /** Steady (non-pulsing) glow in `color` around the icon - e.g. voice while transmitting. Independent of criticalThreshold's pulse. */
  glowing?: boolean;
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
 *
 * Styled via HudIcon.module.scss (CSS Modules + Sass), not Tailwind
 * utility classes like the rest of the app - see that file's own comment.
 */
export const HudIcon: Component<HudIconProps> = (props) => {
  const clamped = () => Math.max(0, Math.min(100, props.value));
  const threshold = () => props.criticalThreshold ?? DEFAULT_CRITICAL_THRESHOLD;
  // createMemo (not a plain getter) so this only re-evaluates to a NEW
  // boolean when the critical state actually flips, not on every health
  // tick - a plain () => ... getter re-runs the class list on every
  // single value change (health is pushed every frame), which reassigns
  // className every time and restarts the CSS animation from 0%, making
  // the glow flicker/reset instead of pulsing smoothly.
  const isCritical = createMemo(() => !props.static && threshold() > 0 && clamped() <= threshold());

  const rootClass = () =>
    [styles.root, isCritical() && styles.critical, props.glowing && styles.glowing, props.class].filter(Boolean).join(" ");

  return (
    <div class={rootClass()} style={{ "--glow-color": props.color }}>
      <div class={styles.fill} />
      <svg width={SIZE} height={SIZE} class={styles.ring}>
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
            class={styles.ringProgress}
          />
        </Show>
      </svg>
      <div class={props.static ? `${styles.glyph} ${styles.glyphStatic}` : styles.glyph}>{props.icon}</div>
    </div>
  );
};
