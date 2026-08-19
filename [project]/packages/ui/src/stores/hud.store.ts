import { createStore } from "solid-js/store";
import type { HudStats } from "@/types/hud";
import { mta } from "@/lib/mta/MtaBridge";

const [stats, setStats] = createStore<HudStats>({
  health: 100,
  hunger: 100,
  thirst: 100,
  voiceActive: false,
});

export const hudStore = {
  stats,
};

mta.on("hud.updated", (data) => {
  setStats(data as HudStats);
});
