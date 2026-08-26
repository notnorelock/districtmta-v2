import { type Component, For, Show, createMemo } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { radioStore } from "@/stores/radio.store";
import { weatherStore } from "@/stores/weather.store";
import { RadioCard } from "./RadioCard";
import { WeatherCard } from "./WeatherCard";
import styles from "./TopCenterStack.module.scss";

type SlotKey = "radio" | "weather";

/**
 * Owns the shared top-center dock (fixed/centered/z-index) for both
 * RadioCard and WeatherCard - they used to each carry their own
 * `fixed left-1/2 top-6` positioning and independent <Transition>, which
 * put both cards in the exact same spot whenever visible at once (e.g.
 * driving through a city border while the radio card is still showing),
 * and made the surviving card SNAP into the vacated slot the instant the
 * other one unmounted instead of sliding smoothly.
 *
 * Both cards' actual content now lives in RadioCard/WeatherCard as plain
 * (props-driven, no own store/Transition read) components, rendered here
 * through ONE <For> inside ONE <TransitionGroup> - the same
 * "one list, one TransitionGroup, moveClass does the FLIP-based reflow"
 * shape HudBar.tsx already uses for its icon row. Radio is always listed
 * before weather when both are visible, matching this stack's own visual
 * top-to-bottom order regardless of which one fired most recently.
 *
 * <For>'s list is a plain array of KEYS ("radio"/"weather"), not objects
 * carrying the card content itself - each render function below re-reads
 * the store directly instead of closing over a snapshot, so
 * loading/stations/etc updating WITHOUT the card itself entering/leaving
 * doesn't produce a new array reference and doesn't retrigger <For>'s own
 * add/remove/move diffing (that only cares about the "radio"/"weather"
 * strings, which are stable primitives, not fresh objects every memo run).
 */
export const TopCenterStack: Component = () => {
  const keys = createMemo<SlotKey[]>(() => {
    const active: SlotKey[] = [];
    if (radioStore.station() !== null) active.push("radio");
    if (weatherStore.current() !== null) active.push("weather");
    return active;
  });

  return (
    <div class={`pointer-events-none fixed left-1/2 top-6 z-40 -translate-x-1/2 ${styles.dock}`}>
      <TransitionGroup
        enterActiveClass={styles.slideEnterActive}
        exitActiveClass={styles.slideExitActive}
        enterClass={styles.slideEnterFrom}
        exitToClass={styles.slideExitTo}
        moveClass={styles.slideMove}
      >
        <For each={keys()}>
          {(key) => (
            <div class={styles.slot}>
              <Show when={key === "radio"}>
                <RadioCard station={radioStore.station() ?? "off"} loading={radioStore.loading()} stations={radioStore.stations()} />
              </Show>
              <Show when={key === "weather" && weatherStore.current()}>{(weather) => <WeatherCard weather={weather()} />}</Show>
            </div>
          )}
        </For>
      </TransitionGroup>
    </div>
  );
};
