import { type Component, type JSX, For, Show } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { Volume1, Mic, Megaphone } from "lucide-solid";
import { voiceStore } from "@/stores/voice.store";
import type { VoiceMode } from "@/types/voice";
import styles from "./VoiceIndicator.module.scss";

const ICON_SIZE = 14;

// Distinct icon shape per mode (not just color) so it reads at a glance,
// same reasoning as HudBar's per-stat icons - color-coded too (see
// VoiceIndicator.module.scss's .icon variants) since the user asked for
// nearby speakers' mode to be visible, not just that they're talking.
const MODE_ICON: Record<VoiceMode, () => JSX.Element> = {
  whisper: () => <Volume1 size={ICON_SIZE} />,
  talk: () => <Mic size={ICON_SIZE} />,
  shout: () => <Megaphone size={ICON_SIZE} />,
};

const MODE_ICON_CLASS: Record<VoiceMode, string> = {
  whisper: styles.iconWhisper ?? "",
  talk: styles.iconTalk ?? "",
  shout: styles.iconShout ?? "",
};

/**
 * "Who's talking nearby" list - gm_voice/client/VoiceState.lua's own
 * proximity talking-list, pushed independently of HudBar's voiceActive
 * (which only reflects whether the LOCAL player is talking). Lives in the
 * CEF HUD rather than a dxDraw overlay - dxGUI is reserved for small
 * one-off admin tools (see AdminGuiWindow.lua), the real always-on HUD is
 * this CEF surface.
 */
export const VoiceIndicator: Component = () => {
  return (
    <Show when={voiceStore.nearbySpeakers().length > 0}>
      <div class={styles.list}>
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
                <span class={`${styles.icon} ${MODE_ICON_CLASS[speaker.mode]}`}>{MODE_ICON[speaker.mode]()}</span>
                <span class={styles.name}>{speaker.name}</span>
              </div>
            )}
          </For>
        </TransitionGroup>
      </div>
    </Show>
  );
};
