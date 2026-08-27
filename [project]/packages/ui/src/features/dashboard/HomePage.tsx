import type { Component } from "solid-js";
import { t } from "@/i18n";
import { useRevealOnScroll } from "@/components/common/useRevealOnScroll";
import styles from "./DashboardOverlay.module.scss";

/**
 * "Strona główna" dashboard page - empty placeholder for now. The
 * screenshots this dashboard is modeled on show daily-quest progress/
 * reward content here, but no quest/reward system exists anywhere in
 * this codebase yet (see NAV_ITEMS' own comment in DashboardView.tsx) -
 * shipping fabricated data would be worse than an honest "coming soon".
 * Replace once a real home-page system exists.
 */
export const HomePage: Component = () => {
  const { ref, visible } = useRevealOnScroll();

  return (
    <div ref={ref} class={`${styles.placeholder} reveal-up ${visible() ? "reveal-up-visible" : ""}`}>
      <span class={`${styles.placeholderText} font-mono uppercase tracking-widest`}>{t()("dashboard.home.placeholder")}</span>
    </div>
  );
};
