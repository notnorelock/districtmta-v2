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

export const hudStore = {
  stats,
};

mta.on("hud.updated", (data) => {
  setStats(data as HudStats);
});
