import { createSignal } from "solid-js";
import type { WeatherData } from "@/types/weather";
import { mta } from "@/lib/mta/MtaBridge";

// How long the card stays up after a region's weather is (re)pushed -
// same auto-hide shape as RadioCard/radio.store.ts, just a plain timeout
// here (no loading/buffering state to juggle in between).
const SHOW_DURATION_MS = 5000;

// null = card hidden - either nothing pushed yet, or the SHOW_DURATION_MS
// timeout above already fired. Every push (region change AND the hourly
// server-side reroll broadcast - see WeatherService.lua) restarts the
// timer, same as RadioCard's own "cycling several times in a row keeps
// refreshing, not stacking" behavior.
const [current, setCurrent] = createSignal<WeatherData | null>(null);
let hideTimer: number | undefined;

export const weatherStore = {
  current,
};

mta.on("weather.current", (data) => {
  window.clearTimeout(hideTimer);
  setCurrent(data as WeatherData);
  hideTimer = window.setTimeout(() => setCurrent(null), SHOW_DURATION_MS);
});
