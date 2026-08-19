import { createSignal } from "solid-js";
import type { RadioStation } from "@/types/radio";
import { mta } from "@/lib/mta/MtaBridge";

/**
 * Mirrors the payload shape gm_radio/client/RadioState.lua pushes over
 * "radio.stationChanged" - always a { station, loading } object, never a
 * bare value. Lua's own `nil` can't cross the exports.core_ui:uiPushEvent
 * call (a nil argument is dropped, not passed through) and can't be a
 * table field's value either (assigning nil to a table field removes the
 * key), so the Lua side normalizes "off" to `station = false` - false is
 * what arrives here for "off", not null/undefined.
 */
interface RadioStationChangedPayload {
  station: RadioStation | false;
  loading: boolean;
}

// null = "off"/hidden in this store's own signal - gm_radio pushes
// { station: false } both when the radio is explicitly turned off and a
// few seconds after a station change (auto-hide), not just on vehicle exit.
const [station, setStation] = createSignal<RadioStation | null>(null);
// True from the moment playSound() is called until onClientSoundStream
// confirms the stream actually started (or failed) - see RadioState.lua.
const [loading, setLoading] = createSignal(false);

export const radioStore = {
  station,
  loading,
};

mta.on("radio.stationChanged", (data) => {
  const payload = data as RadioStationChangedPayload;
  setStation(payload.station || null);
  setLoading(payload.loading);
});
