import { type Component, For, Show, createSignal } from "solid-js";
import { User, SlidersHorizontal } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { Switch, SwitchControl, SwitchThumb } from "@/components/ui/Switch";
import { settingsStore } from "@/stores/settings.store";
import { SETTINGS_REGISTRY } from "@/features/settings/settingsRegistry";
import { AccountTab } from "./AccountTab";
import { t } from "@/i18n";
import styles from "./DashboardOverlay.module.scss";

type DashboardTab = "account" | "settings";

/**
 * F10 player dashboard - Account (info + change password) and Settings
 * (gameplay toggles, gm_settings' own registry-driven list, unchanged
 * internals) tabs. Opened/closed by gm_settings/client/SettingsState.lua's
 * F10 keybind + right-click cursor toggle - orthogonal to which tab is
 * showing. Own "dashboard" overlay key (was "settings" before this panel
 * grew beyond a single toggle list).
 */
export const DashboardOverlay: Component = () => {
  const [tab, setTab] = createSignal<DashboardTab>("account");

  return (
    <Overlay name="dashboard" transitionName="dashboard">
      <div class={styles.root}>
        <div class={styles.panel}>
          <div class={styles.header}>
            <span class={styles.title}>{t()("dashboard.title")}</span>
            <div class={styles.tabs}>
              <button
                type="button"
                class={`${styles.tabButton} ${tab() === "account" ? styles.tabButtonActive : ""}`}
                onClick={() => setTab("account")}
              >
                <User size={14} />
                {t()("dashboard.tab.account")}
              </button>
              <button
                type="button"
                class={`${styles.tabButton} ${tab() === "settings" ? styles.tabButtonActive : ""}`}
                onClick={() => setTab("settings")}
              >
                <SlidersHorizontal size={14} />
                {t()("dashboard.tab.settings")}
              </button>
            </div>
          </div>

          <Show when={tab() === "account"}>
            <AccountTab />
          </Show>

          <Show when={tab() === "settings"}>
            <div class={styles.listWrap}>
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
          </Show>
        </div>
      </div>
    </Overlay>
  );
};
