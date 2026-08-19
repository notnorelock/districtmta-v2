import { type Component, Show } from "solid-js";
import { Transition } from "solid-transition-group";
import { Radio, LoaderCircle, SkipBack, SkipForward } from "lucide-solid";
import { radioStore } from "@/stores/radio.store";
import styles from "./RadioCard.module.scss";

const VISUALIZER_BAR_COUNT = 4;

/**
 * Vehicle radio "now playing" card - docked top-center, matches the
 * reference screenshot: cover icon + station name/subtitle row on top,
 * a thin divider, then a footer row with prev/next glyphs bracketing a
 * static "Muzyka z telefonu" label on the left and the current station
 * name on the right. Shown by gm_radio/client/RadioState.lua on every
 * station change and auto-hidden a few seconds later (or immediately on
 * radio-off/vehicle exit) - see radio.store.ts. There's no real
 * track-title metadata from a plain audio stream URL, so the subtitle is
 * a static label rather than a fabricated song name.
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
          {(station) => (
            <div class={styles.card}>
              <div class={styles.row}>
                <div class={styles.cover}>
                  <Show when={!radioStore.loading()} fallback={<LoaderCircle size={20} class={styles.spinner} />}>
                    <Radio size={20} />
                  </Show>
                </div>
                <div class={styles.info}>
                  <span class={styles.stationName}>{station().name}</span>
                  <span class={styles.subtitle}>{radioStore.loading() ? "Buforowanie..." : "Radio pojazdu"}</span>
                </div>
                <Show when={!radioStore.loading()}>
                  <div class={styles.visualizer} aria-hidden="true">
                    {Array.from({ length: VISUALIZER_BAR_COUNT }, (_, index) => (
                      <span class={styles.visualizerBar} style={{ "animation-delay": `${index * 0.15}s` }} />
                    ))}
                  </div>
                </Show>
              </div>
              <div class={styles.footer}>
                <SkipBack size={13} class={styles.footerIcon} />
                <span class={styles.footerLabelLeft}>Muzyka z telefonu</span>
                <span class={styles.footerLabelRight}>{station().name}</span>
                <SkipForward size={13} class={styles.footerIcon} />
              </div>
            </div>
          )}
        </Show>
      </Transition>
    </div>
  );
};
