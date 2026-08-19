import type { Component } from "solid-js";
import { Show } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { Heart, UtensilsCrossed, Droplet, Wind, Volume2 } from "lucide-solid";
import { HudIcon } from "./HudIcon";
import { hudStore } from "@/stores/hud.store";
import styles from "./HudBar.module.scss";

const ICON_SIZE = 18;

const HEALTH_COLOR = "#e5484d";
const HUNGER_COLOR = "#f2b84b";
const THIRST_COLOR = "#3ba7e0";
const OXYGEN_COLOR = "#60a5fa";
const VOICE_COLOR_ACTIVE = "#3dd68c";

export const HudBar: Component = () => {
  return (
    <div class={styles.bar}>
      {/* Every icon lives inside this one TransitionGroup, each wrapped in
          its own <Show> - not just the drowning icon - so any icon that
          starts/stops being conditionally shown (now or later) gets the
          same enter/leave (styles.slide*, see HudBar.module.scss) AND
          makes its siblings glide into the freed/reclaimed slot via
          moveClass (FLIP-based, auto-applied by TransitionGroup to every
          sibling whose position shifts) instead of snapping there
          instantly. Always-visible icons use when={true} - costs nothing,
          keeps the whole row on one consistent animated-list mechanism. */}
      <TransitionGroup
        enterActiveClass={styles.slideEnterActive}
        exitActiveClass={styles.slideExitActive}
        enterClass={styles.slideEnterFrom}
        exitToClass={styles.slideExitTo}
        moveClass={styles.slideMove}
      >
        {/* Health stays first in source order on purpose - TransitionGroup/
            <For>-style lists render in JSX order, so a conditional icon
            placed before it (like drowning used to be) would shove health
            out of the leading slot every time it mounts. */}
        <Show when={true}>
          <HudIcon value={hudStore.stats.health} color={HEALTH_COLOR} icon={<Heart size={ICON_SIZE} />} />
        </Show>
        <Show when={true}>
          <HudIcon value={hudStore.stats.hunger} color={HUNGER_COLOR} icon={<UtensilsCrossed size={ICON_SIZE} />} />
        </Show>
        <Show when={true}>
          <HudIcon value={hudStore.stats.thirst} color={THIRST_COLOR} icon={<Droplet size={ICON_SIZE} />} />
        </Show>
        <Show when={true}>
          <HudIcon
            value={100}
            static={!hudStore.stats.voiceActive}
            color={VOICE_COLOR_ACTIVE}
            icon={<Volume2 size={ICON_SIZE} />}
          />
        </Show>
        <Show when={hudStore.stats.drowning}>
          <HudIcon value={hudStore.stats.oxygen} color={OXYGEN_COLOR} icon={<Wind size={ICON_SIZE} />} />
        </Show>
      </TransitionGroup>
    </div>
  );
};
