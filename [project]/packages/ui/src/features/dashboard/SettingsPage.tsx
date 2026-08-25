import { type Component, For } from "solid-js";
import { Switch, SwitchControl, SwitchThumb } from "@/components/ui/Switch";
import { settingsStore } from "@/stores/settings.store";
import { SETTINGS_REGISTRY } from "@/features/settings/settingsRegistry";
import { t } from "@/i18n";
import styles from "./DashboardOverlay.module.scss";

/** "Ustawienia" dashboard page - the gameplay-toggle list, unchanged
 * internals from the original DashboardOverlay/DashboardView (see
 * gm_settings/server/SettingsRegistry.lua for the whitelist backend). */
export const SettingsPage: Component = () => (
  <div class={styles.listWrap}>
    <span class={`${styles.eyebrow} mb-3`}>{t()("dashboard.settings.eyebrow")}</span>
    <For each={SETTINGS_REGISTRY}>
      {(toggle) => (
        <div class={styles.row}>
          <span class={styles.rowLabel}>{t()(toggle.labelKey)}</span>
          <Switch checked={settingsStore.isEnabled(toggle.id)} onChange={(enabled) => settingsStore.toggle(toggle.id, enabled)}>
            <SwitchControl>
              <SwitchThumb />
            </SwitchControl>
          </Switch>
        </div>
      )}
    </For>
  </div>
);
