import type { Component } from "solid-js";
import { Radio, LoaderCircle, SkipBack, SkipForward } from "lucide-solid";
import { Show } from "solid-js";
import type { RadioStation } from "@/types/radio";
import { t } from "@/i18n";
import styles from "./RadioCard.module.scss";

const VISUALIZER_BAR_COUNT = 4;

/**
 * Vehicle radio "now playing" card content - cover icon + station name/
 * subtitle row on top, a thin divider, then a footer row with prev/next
 * glyphs bracketing a static "Muzyka z telefonu" label on the left and
 * the current station name on the right. Mounted (and unmounted a few
 * seconds later) by TopCenterStack's own TransitionGroup, driven by
 * radio.store.ts - see that file's own module comment for the auto-hide
 * shape, and TopCenterStack.tsx for why this only renders bare card
 * content now instead of owning its own <Transition>/positioning.
 *
 * `station === "off"` (scrolled past the last station, or a vehicle
 * explicitly silenced) still renders the card briefly with an "off"
 * message instead of vanishing silently - otherwise scrolling gives no
 * feedback that the radio actually turned off. This reuses the exact same
 * card/row/footer structure as the playing state (just with different
 * content) rather than a differently-shaped "off" variant.
 *
 * The cover shows a spinning loader while the stream is buffering
 * (RadioState.lua's onClientSoundStream), and a small bar visualizer once
 * it's actually playing. MTA's playSound gives no access to real
 * frequency/amplitude data from the stream, so the bars are a purely
 * cosmetic CSS animation (staggered infinite keyframes), not a real audio
 * analyzer.
 *
 * The footer's right-hand label is the UPCOMING station (what
 * skip-forward would switch to), not the one currently playing - mirrors
 * RadioService.lua's own index math server-side: "off" sits at index 0,
 * STATIONS[1..N] after it, wrapping around in either direction.
 */
export interface RadioCardProps {
  station: RadioStation | "off";
  loading: boolean;
  stations: RadioStation[];
}

export const RadioCard: Component<RadioCardProps> = (props) => {
  const isOff = () => props.station === "off";
  const stationName = () => (isOff() ? t()("radio.off") : (props.station as RadioStation).name);

  const nextStationName = () => {
    if (props.stations.length === 0) return t()("radio.off");

    const currentIndex = isOff() ? 0 : props.stations.findIndex((entry) => entry.url === (props.station as RadioStation).url) + 1;

    const nextIndex = currentIndex + 1 > props.stations.length ? 0 : currentIndex + 1;
    const nextStation = nextIndex === 0 ? undefined : props.stations[nextIndex - 1];
    return nextStation ? nextStation.name : t()("radio.off");
  };

  return (
    <div class={styles.card}>
      <div class={styles.row}>
        <div class={`${styles.cover} ${isOff() ? styles.coverOff : ""}`}>
          <Show
            when={!isOff() && props.loading}
            fallback={<Radio size={20} />}
          >
            <LoaderCircle size={20} class={styles.spinner} />
          </Show>
        </div>
        <div class={styles.info}>
          <span class={styles.stationName}>{stationName()}</span>
          <Show when={!isOff()}>
            <span class={styles.subtitle}>{props.loading ? t()("radio.buffering") : t()("radio.subtitle")}</span>
          </Show>
        </div>
        <Show when={!isOff() && !props.loading}>
          <div class={styles.visualizer} aria-hidden="true">
            {Array.from({ length: VISUALIZER_BAR_COUNT }, (_, index) => (
              <span class={styles.visualizerBar} style={{ "animation-delay": `${index * 0.15}s` }} />
            ))}
          </div>
        </Show>
      </div>
      <div class={styles.footer}>
        <SkipBack size={13} class={styles.footerIcon} />
        <span class={styles.footerLabelLeft}>{t()("radio.footerLabel")}</span>
        <span class={styles.footerLabelRight}>{nextStationName()}</span>
        <SkipForward size={13} class={styles.footerIcon} />
      </div>
    </div>
  );
};
