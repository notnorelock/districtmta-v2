import { type Component, createMemo, type JSX, For, Show } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { voiceStore } from "@/stores/voice.store";
import { hudStore } from "@/stores/hud.store";
import type { VoiceMode } from "@/types/voice";
import styles from "./VoiceIndicator.module.scss";

const WAVE_BAR_COUNT = 4;
// Gap between the radar's right edge and the list, px.
const RADAR_GAP_PX = 12;

const MODE_WAVE_CLASS: Record<VoiceMode, string> = {
  whisper: styles.waveWhisper ?? "",
  talk: styles.waveTalk ?? "",
  shout: styles.waveShout ?? "",
};

/**
 * "Who's talking nearby" list - gm_voice/client/VoiceState.lua's own
 * proximity talking-list, pushed independently of HudBar's voiceActive
 * (which only reflects whether the LOCAL player is talking). Lives in the
 * CEF HUD rather than a dxDraw overlay - dxGUI is reserved for small
 * one-off admin tools (see AdminGuiWindow.lua), the real always-on HUD is
 * this CEF surface.
 *
 * Each row shows an animated bar "waveform" (same cosmetic technique as
 * RadioCard's visualizer - MTA's voice chat gives no real amplitude data
 * per remote player, so this is a staggered CSS keyframe loop, not an
 * actual audio analyzer) instead of a static mic icon, colored/scaled per
 * talk mode so whisper/talk/shout still read apart at a glance.
 *
 * Docks directly to the right of ui_hud's own native dxDraw
 * RadarComponent (bottom-left) when it's visible, using the real
 * screen-space box hud.store.ts gets from HudState.lua's "hud.updated"
 * push (radarPosition/radarVisible - see RadarComponent.lua's own
 * getPosition()). Lua's x/y there are dxDraw screen coordinates (y from
 * the TOP of the screen) - CSS `top` maps to that directly, `bottom`
 * would be wrong (it's measured from the screen's bottom edge instead,
 * which is what put the list on top of the radar instead of beside it).
 * Falls back to the fixed bottom-right .list position (see
 * VoiceIndicator.module.scss) whenever the radar is hidden or the
 * position hasn't arrived yet.
 */
export const VoiceIndicator: Component = () => {
  const dockStyle = createMemo<JSX.CSSProperties | undefined>(() => {
    const position = hudStore.stats.radarPosition;
    if (!hudStore.stats.radarVisible || !position) {
      return undefined;
    }

    return {
      left: `${position.x + position.w + RADAR_GAP_PX}px`,
      right: "auto",
      top: `${position.y}px`,
      bottom: "auto",
      "flex-direction": "column",
      "align-items": "flex-start",
    };
  });

  return (
    <Show when={voiceStore.nearbySpeakers().length > 0}>
      <div class={styles.list} style={dockStyle()}>
        <TransitionGroup
          enterActiveClass={styles.rowEnterActive}
          exitActiveClass={styles.rowExitActive}
          enterClass={styles.rowEnterFrom}
          exitToClass={styles.rowExitTo}
          moveClass={styles.rowMove}
        >
          <For each={voiceStore.nearbySpeakers()}>
            {(speaker) => (
              <div class={styles.row}>
                <div class={`${styles.wave} ${MODE_WAVE_CLASS[speaker.mode]}`} aria-hidden="true">
                  {Array.from({ length: WAVE_BAR_COUNT }, (_, index) => (
                    <span class={styles.waveBar} style={{ "animation-delay": `${index * 0.12}s` }} />
                  ))}
                </div>
                <span class={styles.name}>{speaker.name}</span>
              </div>
            )}
          </For>
        </TransitionGroup>
      </div>
    </Show>
  );
};
