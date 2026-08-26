import { type Component, For, Show, createSignal } from "solid-js";
import { Home, SlidersHorizontal, UserCog, ClipboardCheck, Gift, Gavel, Car } from "lucide-solid";
import { authStore } from "@/stores/auth.store";
import { Logo } from "@/components/common/Logo";
import { Progress } from "@/components/ui/Progress";
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
// systems that do not exist yet anywhere in this codebase (quests, daily
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

// Placeholder-only bounds for the topbar level/XP bar - no level/XP/
// reputation system exists anywhere in this codebase yet (confirmed via
// project-wide grep of [core]). Purely to match the reference
// screenshot's "25 [====progress====] 26" shape - not wired to any real
// data. Replace once a real progression system exists.
const PLACEHOLDER_LEVEL_CURRENT = 25;
const PLACEHOLDER_LEVEL_NEXT = 26;
const PLACEHOLDER_LEVEL_PROGRESS = 35; // percent

/**
 * F10 player dashboard - a real blocking CEF window (see
 * ui_dashboard/client/DashboardState.lua), not an additive overlay.
 * Full-width top navbar (logo image, centered level/XP bar, avatar/name/role)
 * above a vertical nav-only sidebar + content pane. Opened/closed by
 * DashboardState.lua's F10 keybind via UI.open/UI.close
 * (Enums.UiWindow.DASHBOARD) - cursor/GUI-input/weapon lock are all
 * automatic, handled by core_ui/client/ui/BrowserManager.lua, same as
 * the login/spawn-select windows. Only "Strona główna" (home) and
 * "Ustawienia" (settings) and "Ustawienia konta" (accountSettings) are
 * functional in v1 - see NAV_ITEMS' own comment for the other 4.
 */
export const DashboardView: Component = () => {
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
    <div class={styles.root}>
      <header class={styles.topbar}>
        <Logo markHeightClass="h-7" wordmarkHeightClass="h-5" />

        {/* Placeholder only - see PLACEHOLDER_LEVEL_* comment above. */}
        <div class={styles.topbarLevelBlock}>
          <span class={styles.topbarLevelNumber}>{PLACEHOLDER_LEVEL_CURRENT}</span>
          <Progress value={PLACEHOLDER_LEVEL_PROGRESS} class="w-48" />
          <span class={styles.topbarLevelNumber}>{PLACEHOLDER_LEVEL_NEXT}</span>
        </div>

        <div class={styles.topbarIdentity}>
          <div class={styles.identity}>
            <span class={styles.name}>{account()?.login ?? ""}</span>
            <span class={styles.role}>{account() ? (ROLE_LABEL[account()!.role] ?? account()!.role) : ""}</span>
          </div>
          <div class={styles.avatar} />
        </div>
      </header>

      <div class={styles.body}>
        <div class={styles.sidebar}>
          <span class={styles.eyebrow}>{t()("dashboard.eyebrow")}</span>

          <nav class={styles.nav}>
            <For each={NAV_ITEMS}>
              {(item) => (
                <button
                  type="button"
                  class={`${styles.navRow} ${page() === item.id && item.active ? styles.navRowActive : ""} ${!item.active ? styles.navRowDisabled : ""}`}
                  onClick={() => selectPage(item)}
                >
                  <item.icon size={16} />
                  <span class={`${styles.navLabel} uppercase tracking-wide`}>{t()(item.labelKey)}</span>
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
    </div>
  );
};
