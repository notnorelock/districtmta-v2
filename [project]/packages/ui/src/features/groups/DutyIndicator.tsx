import { type Component, Show } from "solid-js";
import { Shield } from "lucide-solid";
import { t } from "@/i18n";
import { groupStore } from "@/stores/group.store";
import styles from "./DutyIndicator.module.scss";

const TYPE_COLOR: Record<string, string> = {
  gang: "#e5484d",
  organization: "#3ba7e0",
  fraction: "#f2b84b",
};

function formatElapsed(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

/**
 * Compact duty pill, docked directly above HudBar.tsx's own icon row
 * (same bottom-right corner, see DutyIndicator.module.scss's .dock) -
 * rendered from INSIDE App.tsx's "hud" Overlay, not its own separate
 * Overlay/Transition, so it slides in/out together with the rest of the
 * HUD (HudBar/VoiceIndicator) for free via that Overlay's own
 * .hud-enter-from/.hud-exit-to (globals.css), instead of fighting it with
 * a second independent transition. Visual language matches HudIcon.tsx's
 * small rounded-square glass tiles (bg-popover fill, colored ring/glow)
 * rather than RadioCard.tsx's larger standalone card - this sits right
 * next to the HUD row, so it needs to read as part of the same family,
 * not a competing floating panel.
 */
export const DutyIndicator: Component = () => {
  return (
    <Show when={groupStore.duty.active() && groupStore.duty.info()}>
      {(info) => (
        <div class={styles.dock} style={{ "--duty-color": TYPE_COLOR[info().groupType] ?? TYPE_COLOR.organization }}>
          <div class={styles.pill}>
            <div class={styles.icon}>
              <Shield size={16} />
            </div>
            <div class={styles.info}>
              <span class={styles.groupName}>{info().groupName}</span>
              <span class={styles.rankName}>{info().rankName}</span>
            </div>
            <span class={styles.elapsed}>{formatElapsed(groupStore.duty.totalSeconds())}</span>
          </div>
          <span class={styles.hint}>{t()("groups.duty.toggleHint")}</span>
        </div>
      )}
    </Show>
  );
};
