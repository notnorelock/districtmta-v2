import { type Component, Show } from "solid-js";
import { Transition } from "solid-transition-group";
import { Radio, LoaderCircle, SkipBack, SkipForward } from "lucide-solid";
import { radioStore } from "@/stores/radio.store";
import type { RadioStation } from "@/types/radio";
import { t } from "@/i18n";
import styles from "./RadioCard.module.scss";

const VISUALIZER_BAR_COUNT = 4;

/**
 * Vehicle radio "now playing" card - docked top-center, matches the
 * reference screenshot: cover icon + station name/subtitle row on top,
 * a thin divider, then a footer row with prev/next glyphs bracketing a
 * static "Muzyka z telefonu" label on the left and the current station
 * name on the right. Shown by gm_radio/client/RadioState.lua on every
 * station change and auto-hidden a few seconds later (or immediately on
 * vehicle exit) - see radio.store.ts. There's no real track-title
 * metadata from a plain audio stream URL, so the subtitle is a static
 * label rather than a fabricated song name.
 *
 * radioStore.station() === "off" (scrolled past the last station, or a
 * vehicle explicitly silenced) still renders the card briefly with an
 * "off" message instead of vanishing silently - otherwise scrolling
 * gives no feedback that the radio actually turned off. This reuses the
 * exact same card/row/footer structure as the playing state (just with
 * different content) rather than a differently-shaped "off" variant -
 * two differently-sized DOM shapes under the same <Transition> read as
 * two different elements, so switching between them pushed/shoved the
 * old card out instead of smoothly swapping content in place.
 *
 * The cover shows a spinning loader while the stream is buffering
 * (radioStore.loading, driven by onClientSoundStream - see
 * RadioState.lua), and a small bar visualizer once it's actually
 * playing. MTA's playSound gives no access to real frequency/amplitude
 * data from the stream, so the bars are a purely cosmetic CSS animation
 * (staggered infinite keyframes), not a real audio analyzer.
 */
export const RadioCard: Component = () => {
  return (
    <div class={styles.dock}>
      <Transition
        enterActiveClass={styles.cardEnterActive}
        exitActiveClass={styles.cardExitActive}
        enterClass={styles.cardEnterFrom}
        exitToClass={styles.cardExitTo}
      >
        <Show when={radioStore.station()}>
          {(station) => {
            const isOff = () => station() === "off";
            const stationName = () => (isOff() ? t()("radio.off") : (station() as RadioStation).name);

            return (
              <div class={styles.card}>
                <div class={styles.row}>
                  <div class={`${styles.cover} ${isOff() ? styles.coverOff : ""}`}>
                    <Show
                      when={!isOff() && radioStore.loading()}
                      fallback={<Radio size={20} />}
                    >
                      <LoaderCircle size={20} class={styles.spinner} />
                    </Show>
                  </div>
                  <div class={styles.info}>
                    <span class={styles.stationName}>{stationName()}</span>
                    <Show when={!isOff()}>
                      <span class={styles.subtitle}>{radioStore.loading() ? t()("radio.buffering") : t()("radio.subtitle")}</span>
                    </Show>
                  </div>
                  <Show when={!isOff() && !radioStore.loading()}>
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
                  <span class={styles.footerLabelRight}>{stationName()}</span>
                  <SkipForward size={13} class={styles.footerIcon} />
                </div>
              </div>
            );
          }}
        </Show>
      </Transition>
    </div>
  );
};
