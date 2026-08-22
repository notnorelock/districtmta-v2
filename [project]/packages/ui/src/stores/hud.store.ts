import { createSignal } from "solid-js";
import { createStore } from "solid-js/store";
import type { HudStats } from "@/types/hud";
import { mta } from "@/lib/mta/MtaBridge";

const [stats, setStats] = createStore<HudStats>({
  health: 100,
  hunger: 100,
  thirst: 100,
  oxygen: 100,
  drowning: false,
  voiceActive: false,
  voiceLevel: 0,
  radarVisible: false,
  radarPosition: false,
});

interface VoiceModeChange {
  label: string;
  /** Bumped on every push (even to the same label, e.g. a full whisper->talk->shout->whisper cycle) so HudBar.tsx's own effect always re-fires and restarts its auto-hide timer instead of missing a repeat value. */
  token: number;
}

// "Mowa" (TALK) matches VoiceService.lua's own VoiceService.getMode
// fallback - a player who never pressed B is still on TALK server-side,
// so the tooltip should reflect that from the start instead of a generic
// placeholder until the first cycle.
const [voiceModeLabel, setVoiceModeLabel] = createSignal("Mowa");
const [voiceModeChange, setVoiceModeChange] = createSignal<VoiceModeChange | null>(null);
let voiceModeChangeToken = 0;

export const hudStore = {
  stats,
  voiceModeLabel,
  voiceModeChange,
};

mta.on("hud.updated", (data) => {
  setStats(data as HudStats);
});

mta.on("voice.modeChanged", (data) => {
  const payload = data as { mode: string; label: string };
  setVoiceModeLabel(payload.label);
  voiceModeChangeToken += 1;
  setVoiceModeChange({ label: payload.label, token: voiceModeChangeToken });
});
