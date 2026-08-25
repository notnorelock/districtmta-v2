import { type Component, For, Show, createSignal } from "solid-js";
import { Home, SlidersHorizontal, UserCog, ClipboardCheck, Gift, Gavel, Car } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { authStore } from "@/stores/auth.store";
import { HomePage } from "./HomePage";
import { SettingsPage } from "./SettingsPage";
import { AccountSettingsPage, ROLE_LABEL } from "./AccountSettingsPage";
import { t } from "@/i18n";
import styles from "./DashboardOverlay.module.scss";

type DashboardPage = "home" | "quests" | "dailyReward" | "penalties" | "settings" | "accountSettings" | "vehicles";

interface NavItem {
  id: DashboardPage;
  icon: Component<{ size?: number }>;
  labelKey: string;
  active: boolean;
}

// Nav rows, in screenshot order. 4 of 6 are inert placeholders for
// systems that don't exist yet anywhere in this codebase (quests, daily
// reward, penalties, an in-dashboard vehicle list) - confirmed via
// project-wide grep. Clicking an inert row shows a "wkrótce" hint
// instead of switching pages; it never errors. Adding a real page
// later: flip `active` to true here and add its page component to the
// content Show block below - no other layout change needed.
const NAV_ITEMS: NavItem[] = [
  { id: "home", icon: Home, labelKey: "dashboard.nav.home", active: true },
  { id: "quests", icon: ClipboardCheck, labelKey: "dashboard.nav.quests", active: false },
  { id: "dailyReward", icon: Gift, labelKey: "dashboard.nav.dailyReward", active: false },
  { id: "penalties", icon: Gavel, labelKey: "dashboard.nav.penalties", active: false },
  { id: "settings", icon: SlidersHorizontal, labelKey: "dashboard.nav.settings", active: true },
  { id: "accountSettings", icon: UserCog, labelKey: "dashboard.nav.accountSettings", active: true },
  { id: "vehicles", icon: Car, labelKey: "dashboard.nav.vehicles", active: false },
];

/**
 * F10 player dashboard - full-screen sidebar layout (avatar/name/role
 * header, static level/XP placeholder, 6 nav rows) with a right-side
 * content pane. Opened/closed by ui_dashboard/client/DashboardState.lua's
 * F10 keybind + right-click cursor toggle (moved from gm_settings - see
 * that resource's own SettingsState.lua comment). Own "dashboard"
 * overlay key, unchanged since the original small-popup version. Only
 * "Strona główna" (home) and "Ustawienia" (settings) are functional in
 * v1 - see NAV_ITEMS' own comment for the other 4.
 */
export const DashboardOverlay: Component = () => {
  const [page, setPage] = createSignal<DashboardPage>("home");
  const [comingSoon, setComingSoon] = createSignal(false);
  const account = authStore.account;

  const selectPage = (item: NavItem) => {
    if (!item.active) {
      setComingSoon(true);
      window.setTimeout(() => setComingSoon(false), 2000);
      return;
    }
    setPage(item.id);
  };

  return (
    <Overlay name="dashboard" transitionName="dashboard">
      <div class={styles.root}>
        <div class={styles.sidebar}>
          <div class={styles.sidebarHeader}>
            <div class={styles.avatar} />
            <div class={styles.identity}>
              <span class={styles.name}>{account()?.login ?? ""}</span>
              <span class={styles.role}>{account() ? (ROLE_LABEL[account()!.role] ?? account()!.role) : ""}</span>
            </div>
          </div>

          {/* Placeholder only - no level/XP/reputation system exists
              anywhere in this codebase yet (confirmed via project-wide
              grep of [core]). Static label + a fixed-value bar, purely
              to match the reference screenshots' layout - not wired to
              any real data. Replace once a real progression system exists. */}
          <div class={styles.levelBlock}>
            <span class={styles.levelLabel}>{t()("dashboard.level.label")}</span>
            <div class={styles.levelBar}>
              <div class={styles.levelBarFill} style={{ width: "35%" }} />
            </div>
          </div>

          <nav class={styles.nav}>
            <For each={NAV_ITEMS}>
              {(item) => (
                <button
                  type="button"
                  class={`${styles.navRow} ${page() === item.id && item.active ? styles.navRowActive : ""} ${!item.active ? styles.navRowDisabled : ""}`}
                  onClick={() => selectPage(item)}
                >
                  <item.icon size={16} />
                  <span class={styles.navLabel}>{t()(item.labelKey)}</span>
                </button>
              )}
            </For>
          </nav>

          <Show when={comingSoon()}>
            <span class={styles.comingSoonHint}>{t()("dashboard.comingSoon")}</span>
          </Show>
        </div>

        <div class={styles.content}>
          <Show when={page() === "home"}>
            <HomePage />
          </Show>
          <Show when={page() === "settings"}>
            <SettingsPage />
          </Show>
          <Show when={page() === "accountSettings"}>
            <AccountSettingsPage />
          </Show>
        </div>
      </div>
    </Overlay>
  );
};
