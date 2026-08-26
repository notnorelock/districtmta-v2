import { type Component, Show } from "solid-js";
import { Transition } from "solid-transition-group";
import { Sun, CloudRain, CloudSun, Snowflake } from "lucide-solid";
import type { LucideProps } from "lucide-solid";
import { weatherStore } from "@/stores/weather.store";
import type { WeatherIcon } from "@/types/weather";
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
 * Regional weather card - docked top-center (matches the old resource's
 * own fixed placement), shown for a few seconds on region change/reroll
 * then auto-hidden - see weather.store.ts's SHOW_DURATION_MS - same
 * transient-notification shape as RadioCard, not a permanent HUD fixture.
 */
export const WeatherCard: Component = () => {
  return (
    <div class={styles.dock}>
      <Transition
        enterActiveClass={styles.cardEnterActive}
        exitActiveClass={styles.cardExitActive}
        enterClass={styles.cardEnterFrom}
        exitToClass={styles.cardExitTo}
      >
        <Show when={weatherStore.current()}>
          {(weather) => {
            const Icon = ICON_BY_TYPE[weather().icon];
            return (
              <div class={styles.card}>
                <div class={styles.iconWrap}>
                  <Icon size={22} class={ANIM_BY_TYPE[weather().icon]} />
                </div>
                <div class={styles.info}>
                  <span class={styles.city}>{weather().city}</span>
                  <span class={styles.label}>{t()(`weather.${weather().labelKey}`)}</span>
                </div>
              </div>
            );
          }}
        </Show>
      </Transition>
    </div>
  );
};
