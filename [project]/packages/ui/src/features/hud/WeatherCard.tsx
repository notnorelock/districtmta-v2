import { type Component, createMemo } from "solid-js";
import { Dynamic } from "solid-js/web";
import { Sun, CloudRain, CloudSun, Snowflake } from "lucide-solid";
import type { LucideProps } from "lucide-solid";
import type { WeatherData, WeatherIcon } from "@/types/weather";
import { t } from "@/i18n";
import styles from "./WeatherCard.module.scss";

const ICON_BY_TYPE: Record<WeatherIcon, Component<LucideProps>> = {
  sunny: Sun,
  rain: CloudRain,
  partialyCloudy: CloudSun,
  snow: Snowflake,
};

// One small motion cue per weather type, applied to the icon itself
// (iconWrap's background/shape stays static) - see WeatherCard.module.scss
// for each keyframe. Purely cosmetic, no gameplay meaning, and disabled
// entirely under prefers-reduced-motion (same file, that media query
// overrides every one of these back to `none`).
const ANIM_BY_TYPE: Record<WeatherIcon, string | undefined> = {
  sunny: styles.animSunny,
  rain: styles.animRain,
  partialyCloudy: styles.animCloudy,
  snow: styles.animSnow,
};

/**
 * Regional weather card content - shown for a few seconds on region
 * change/reroll then auto-hidden by weather.store.ts's SHOW_DURATION_MS -
 * see TopCenterStack.tsx, which mounts/unmounts this alongside RadioCard
 * inside one shared TransitionGroup (this component only renders bare
 * card content now, no own <Transition>/positioning).
 */
export interface WeatherCardProps {
  weather: WeatherData;
}

export const WeatherCard: Component<WeatherCardProps> = (props) => {
  // TopCenterStack's <For> keys on the constant "weather" string, not on
  // this props object - a reroll while the card is already showing
  // updates `props.weather` in place WITHOUT remounting this component
  // (that's the whole point: no remount means no FLIP-move flicker for a
  // card that isn't actually entering/leaving). The component BODY itself
  // only runs once on mount, so `props.weather.icon` must be read inside
  // a real reactive computation (this memo), not destructured up front,
  // or the icon would freeze on whatever weather was active at mount time.
  // <Dynamic> (not a plain <Icon/> tag) because Icon() itself is the
  // reactive part - JSX's `<SomeCapitalizedTag>` shorthand expects a
  // stable component reference, not an accessor whose RETURNED component
  // can change between calls.
  const Icon = createMemo(() => ICON_BY_TYPE[props.weather.icon]);

  return (
    <div class={styles.card}>
      <div class={styles.iconWrap}>
        <Dynamic component={Icon()} size={22} class={ANIM_BY_TYPE[props.weather.icon]} />
      </div>
      <div class={styles.info}>
        <span class={styles.city}>{props.weather.city}</span>
        <span class={styles.label}>{t()(`weather.${props.weather.labelKey}`)}</span>
      </div>
    </div>
  );
};
