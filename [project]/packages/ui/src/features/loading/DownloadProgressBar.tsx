import { Show, type Component } from "solid-js";
import { Transition } from "solid-transition-group";
import { Progress } from "@/components/ui/Progress";
import { loadingStore } from "@/stores/loading.store";
import { useWindow } from "@/components/common/WindowProvider";
import { authStore } from "@/stores/auth.store";
import { formatBytes } from "@/lib/formatBytes";
import { t } from "@/i18n";
import styles from "./DownloadProgressBar.module.scss";

/**
 * Small dock at the bottom of the screen, informing the player that MTA
 * is still downloading resources IN THE BACKGROUND - for whenever that's
 * still going once the auth screen itself is already up (ResourceCheckScreen,
 * gated on Events.LOADING_READY, already blocks the auth screen from
 * appearing at all until the FIRST full resource-download pass finishes -
 * this dock only ever matters for resources fetched later in the same
 * session, e.g. a mid-session resource restart pulling in new assets).
 * Rendered unconditionally in App.tsx (like BlackoutOverlay/Watermark),
 * not gated behind any particular screen, since a background download
 * can happen while the player is anywhere in the app - but must NEVER be
 * visible AT THE SAME TIME as ResourceCheckScreen (both would otherwise
 * show overlapping download progress during the very first download
 * pass), so isResourceCheckScreenVisible below mirrors App.tsx's own
 * <Match> condition for that screen exactly - keep the two in sync if
 * that condition ever changes.
 */
export const DownloadProgressBar: Component = () => {
  const windowState = useWindow();

  const isResourceCheckScreenVisible = () =>
    authStore.phase() === "checking" || (!windowState.hasOpenedAnyWindow() && windowState.activeWindow() === null);

  const visible = () => {
    if (isResourceCheckScreenVisible()) return false;
    const progress = loadingStore.progress();
    return progress !== null && progress.visible && progress.totalSize > 0;
  };

  return (
    <div class={styles.root}>
      <Transition
        enterActiveClass={styles.cardEnterActive}
        exitActiveClass={styles.cardExitActive}
        enterClass={styles.cardEnterFrom}
        exitToClass={styles.cardExitTo}
      >
        <Show when={visible()}>
          {(() => {
            const progress = loadingStore.progress()!;
            const percent = Math.round((progress.downloadedSize / progress.totalSize) * 100);
            return (
              <div class={styles.card}>
                <div class={styles.info}>
                  <p class={styles.title}>{t()("loading.resourceCheck")}</p>
                  <p class={styles.subtitle}>
                    {formatBytes(progress.downloadedSize)} / {formatBytes(progress.totalSize)}
                  </p>
                </div>
                <Progress value={percent} size="sm" class={styles.bar} />
              </div>
            );
          })()}
        </Show>
      </Transition>
    </div>
  );
};
