import { createSignal } from "solid-js";
import type { RadioStation } from "@/types/radio";
import { mta } from "@/lib/mta/MtaBridge";

/**
 * Mirrors the payload shape gm_radio/client/RadioState.lua pushes over
 * "radio.stationChanged" - always a { station, loading } object, never a
 * bare value. Lua's own `nil` can't cross the exports.core_ui:uiPushEvent
 * call (a nil argument is dropped, not passed through) and can't be a
 * table field's value either (assigning nil to a table field removes the
 * key), so the Lua side normalizes "hidden" to `station = false` and
 * "explicitly turned off (but card still shown briefly)" to the "off"
 * string sentinel - both arrive as those exact values here, never
 * null/undefined.
 */
interface RadioStationChangedPayload {
  station: RadioStation | "off" | false;
  loading: boolean;
}

// null = card hidden entirely. "off" = card shown with a "radio off"
// message (RadioService.setStation(vehicle, nil) or scrolling past the
// last station) - distinct from null so the driver gets confirmation
// scrolling actually turned it off, instead of the card just vanishing.
const [station, setStation] = createSignal<RadioStation | "off" | null>(null);
// True from the moment playSound() is called until onClientSoundStream
// confirms the stream actually started (or failed) - see RadioState.lua.
const [loading, setLoading] = createSignal(false);

export const radioStore = {
  station,
  loading,
};

mta.on("radio.stationChanged", (data) => {
  const payload = data as RadioStationChangedPayload;
  setStation(payload.station === false ? null : payload.station);
  setLoading(payload.loading);
});
