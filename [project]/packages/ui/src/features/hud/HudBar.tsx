import type { Component } from "solid-js";
import { Show, createEffect, createSignal, onCleanup } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { Heart, UtensilsCrossed, Droplet, Wind, Volume2 } from "lucide-solid";
import { HudIcon } from "./HudIcon";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/Tooltip";
import { t } from "@/i18n";
import { hudStore } from "@/stores/hud.store";
import styles from "./HudBar.module.scss";

const ICON_SIZE = 18;

const HEALTH_COLOR = "#e5484d";
const HUNGER_COLOR = "#f2b84b";
const THIRST_COLOR = "#3ba7e0";
const OXYGEN_COLOR = "#60a5fa";
const VOICE_COLOR_ACTIVE = "#3dd68c";

// How long the voice-mode tooltip stays visible after a cycle - short
// enough to not linger, but restarted (not queued) on every VoiceService.lua
// confirmation, so cycling past several modes in quick succession just
// keeps the same tooltip open/refreshed with the latest label instead of
// stacking or flickering.
const VOICE_MODE_TOOLTIP_MS = 4000;

export const HudBar: Component = () => {
  const [voiceTooltipOpen, setVoiceTooltipOpen] = createSignal(false);
  let hideTimer: number | undefined;

  // Every VoiceService.lua confirmation bumps hudStore.voiceModeChange()'s
  // own token (see hud.store.ts), even for a repeat label (a full
  // whisper->talk->shout->whisper cycle) - createEffect re-fires on every
  // token change regardless, so this always restarts the auto-hide timer
  // instead of the tooltip going stale mid-cycle.
  createEffect(() => {
    const change = hudStore.voiceModeChange();
    if (!change) return;

    window.clearTimeout(hideTimer);
    setVoiceTooltipOpen(true);
    hideTimer = window.setTimeout(() => setVoiceTooltipOpen(false), VOICE_MODE_TOOLTIP_MS);
  });

  onCleanup(() => window.clearTimeout(hideTimer));

  return (
    <div class={styles.bar} style={{ bottom: `calc(1rem + ${hudStore.speedoLiftPx()}px)` }}>
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
          <Tooltip placement="top">
            <TooltipTrigger as="div" class={styles.iconTrigger}>
              <HudIcon value={hudStore.stats.health} color={HEALTH_COLOR} icon={<Heart size={ICON_SIZE} />} />
            </TooltipTrigger>
            <TooltipContent>{t()("hud.health.tooltip")}</TooltipContent>
          </Tooltip>
        </Show>
        <Show when={true}>
          <Tooltip placement="top">
            <TooltipTrigger as="div" class={styles.iconTrigger}>
              <HudIcon value={hudStore.stats.hunger} color={HUNGER_COLOR} icon={<UtensilsCrossed size={ICON_SIZE} />} />
            </TooltipTrigger>
            <TooltipContent>{t()("hud.hunger.tooltip")}</TooltipContent>
          </Tooltip>
        </Show>
        <Show when={true}>
          <Tooltip placement="top">
            <TooltipTrigger as="div" class={styles.iconTrigger}>
              <HudIcon value={hudStore.stats.thirst} color={THIRST_COLOR} icon={<Droplet size={ICON_SIZE} />} />
            </TooltipTrigger>
            <TooltipContent>{t()("hud.thirst.tooltip")}</TooltipContent>
          </Tooltip>
        </Show>
        <Show when={true}>
          {/* value tracks voiceLevel (33/66/100 for whisper/talk/shout,
              see HudState.lua) and is ALWAYS filled to the current mode -
              not gated behind voiceActive - so the ring shows "what mode
              am I set to" at a glance even while silent. criticalThreshold={0}
              disables the glow-pulse-when-low behavior other icons use -
              a quiet whisper isn't a "critical" state worth pulsing red.
              glowing (steady, not pulsing - see HudIcon.module.scss's
              .glowing) is the only thing voiceActive drives here -
              highlights the icon for as long as voice is actually
              transmitting, on top of the always-shown mode fill.

              Wrapped in a Tooltip with a fully controlled `open` (not
              hover-driven) - see the voiceTooltipOpen effect above -
              so pressing B to cycle talk mode surfaces the new mode as a
              transient callout over the icon instead of gm_voice's old
              plain outputChatBox line (see Events.VOICE_MODE_CHANGED). */}
          <Tooltip open={voiceTooltipOpen()} onOpenChange={setVoiceTooltipOpen} placement="top">
            <TooltipTrigger as="div" class={styles.voiceTrigger}>
              <HudIcon
                value={hudStore.stats.voiceLevel}
                criticalThreshold={0}
                glowing={hudStore.stats.voiceActive}
                color={VOICE_COLOR_ACTIVE}
                icon={<Volume2 size={ICON_SIZE} />}
              />
            </TooltipTrigger>
            {/* keyed Show, not a plain {hudStore.voiceModeLabel()} text
                expression - Kobalte's TooltipContent wraps its children in
                its own <Show when={contentPresent()}>, which mounts ONCE
                and then stays mounted for as long as `open` stays
                continuously true. A rapid B-cycle (confirmed via
                /browserdebug: the store's voiceModeLabel signal updates
                correctly every press) never toggles `open` back to false
                in between, since setVoiceTooltipOpen(true) is a no-op once
                it's already true - so the plain text expression rendered
                once and never updated again. voiceModeChange() is a FRESH
                object on every push (see hud.store.ts), so keying on it
                forces this subtree to remount on every single press, even
                a same-label one, guaranteeing the shown label is current. */}
            <TooltipContent>
              <Show when={hudStore.voiceModeChange()} keyed fallback={hudStore.voiceModeLabel()}>
                {(change) => change.label}
              </Show>
            </TooltipContent>
          </Tooltip>
        </Show>
        <Show when={hudStore.stats.drowning}>
          <Tooltip placement="top">
            <TooltipTrigger as="div" class={styles.iconTrigger}>
              <HudIcon value={hudStore.stats.oxygen} color={OXYGEN_COLOR} icon={<Wind size={ICON_SIZE} />} />
            </TooltipTrigger>
            <TooltipContent>{t()("hud.oxygen.tooltip")}</TooltipContent>
          </Tooltip>
        </Show>
      </TransitionGroup>
    </div>
  );
};
