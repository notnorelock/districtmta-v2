import type { Component } from "solid-js";
import { Heart, UtensilsCrossed, Droplet, Volume2 } from "lucide-solid";
import { HudIcon } from "./HudIcon";
import { hudStore } from "@/stores/hud.store";

const ICON_SIZE = 18;

const HEALTH_COLOR = "#e5484d";
const HUNGER_COLOR = "#f2b84b";
const THIRST_COLOR = "#3ba7e0";
const VOICE_COLOR_ACTIVE = "#3dd68c";

export const HudBar: Component = () => {
  return (
    <div class="pointer-events-none fixed bottom-4 right-4 z-40 flex gap-2">
      <HudIcon value={hudStore.stats.health} color={HEALTH_COLOR} icon={<Heart size={ICON_SIZE} />} />
      <HudIcon value={hudStore.stats.hunger} color={HUNGER_COLOR} icon={<UtensilsCrossed size={ICON_SIZE} />} />
      <HudIcon value={hudStore.stats.thirst} color={THIRST_COLOR} icon={<Droplet size={ICON_SIZE} />} />
      <HudIcon
        value={100}
        static={!hudStore.stats.voiceActive}
        color={VOICE_COLOR_ACTIVE}
        icon={<Volume2 size={ICON_SIZE} />}
      />
    </div>
  );
};
