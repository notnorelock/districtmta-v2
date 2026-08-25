import { createSignal } from "solid-js";
import type { SettingsSnapshot } from "@/types/settings";
import { mta } from "@/lib/mta/MtaBridge";

const [enabledIds, setEnabledIds] = createSignal<SettingsSnapshot>([]);

function isEnabled(id: string): boolean {
  return enabledIds().includes(id);
}

// Optimistic - flips the signal immediately so the switch never visibly
// lags on click; the server's own SETTINGS_SYNCED reply (a tick later)
// reconciles this to the real state regardless, same "server confirms
// back" shape PUSH_VEHICLE_INTERACTION_STATE already uses. Reasonable
// here specifically because a settings toggle is a pure player
// preference with no gameplay-fairness stake - see SettingsState.lua's
// own comment on why the server trusts a validated toggle value outright.
function toggle(id: string, enabled: boolean) {
  setEnabledIds((current) => (enabled ? [...current, id] : current.filter((existingId) => existingId !== id)));
  mta.notify("settings:toggle", id, enabled);
}

export const settingsStore = {
  enabledIds,
  isEnabled,
  toggle,
};

mta.on("settings.synced", (data) => {
  setEnabledIds((data as SettingsSnapshot) ?? []);
});
