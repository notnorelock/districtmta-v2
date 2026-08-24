import { type Component, Show } from "solid-js";
import { Car } from "lucide-solid";
import { licenseExamStore } from "@/stores/licenseExam.store";
import { groupStore } from "@/stores/group.store";
import { hudStore } from "@/stores/hud.store";
import styles from "./LicenseExamHud.module.scss";

/**
 * Always-visible "current objective" card while a driving license exam
 * is in progress - the one CEF piece the exam actually needs (no sane
 * notification-spam equivalent for a live, changing objective), matching
 * why DutyIndicator.tsx exists as CEF rather than a toast. Rendered from
 * INSIDE App.tsx's "hud" Overlay, not its own separate Overlay, so it
 * slides in/out together with the rest of the HUD for free - same
 * reasoning as DutyIndicator.tsx's own module comment. Pass/fail
 * feedback is NOT shown here - LicenseExamService.lua's own
 * NotificationService.send already covers that via the native toast,
 * matching every other pass/fail moment project-wide.
 *
 * Docks one step above HudBar's own row when DutyIndicator is also
 * showing (groupStore.duty.active()), stacking above it - but drops
 * down to sit directly above HudBar itself when DutyIndicator is
 * absent, instead of always reserving DutyIndicator's spot and leaving
 * a gap underneath it. See LicenseExamHud.module.scss's own
 * .dock/.dockRaised split.
 */
export const LicenseExamHud: Component = () => {
  return (
    <Show when={licenseExamStore.active() && licenseExamStore.info()}>
      {(info) => (
        <div
          class={groupStore.duty.active() ? styles.dockRaised : styles.dock}
          style={{ bottom: `calc(${groupStore.duty.active() ? 8 : 4.5}rem + ${hudStore.speedoLiftPx()}px)` }}
        >
          <div class={styles.card}>
            <div class={styles.icon}>
              <Car size={16} />
            </div>
            <div class={styles.info}>
              <span class={styles.categoryName}>{info().categoryName}</span>
              <span class={styles.objective}>{licenseExamStore.objective()}</span>
            </div>
            <Show when={licenseExamStore.remainingMeters() !== null}>
              <span class={styles.remaining}>{Math.max(0, Math.ceil(licenseExamStore.remainingMeters() ?? 0))}m</span>
            </Show>
          </div>
        </div>
      )}
    </Show>
  );
};
