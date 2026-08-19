import { type Component, Show, createMemo } from "solid-js";
import { Transition } from "solid-transition-group";
import { blackoutStore } from "@/stores/blackout.store";
import { t } from "@/i18n";
import styles from "./BlackoutOverlay.module.scss";

const RING_SIZE = 44;
const RING_STROKE = 3;
const RING_INSET = RING_STROKE / 2;

function formatMMSS(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = Math.floor(totalSeconds % 60);
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

/**
 * Blackout presentation - a pulsing red low-health-style vignette across
 * the whole screen (purely decorative, CSS keyframes, see .vignette below)
 * plus a small card (countdown ring + status text), docked at the bottom
 * center - matches the reference screenshot the user provided. Rendered
 * unconditionally (see App.tsx) with a single <Transition> reacting
 * directly to blackoutStore.secondsRemaining(), same pattern as
 * RadioCard.tsx's dock+card - no outer <Overlay>/OverlayProvider wrapper,
 * since nesting this component's own <Transition> inside <Overlay>'s
 * mode="outin" <Transition> tore the whole subtree down and rebuilt it on
 * every visibility flip, never letting the inner slide transition run.
 * The countdown/self-revive-availability are pushed separately over
 * blackoutStore - server (BlackoutService.lua) is fully authoritative
 * over both, this only renders whatever it's told.
 */
export const BlackoutOverlay: Component = () => {
  const label = createMemo(() => {
    const seconds = blackoutStore.secondsRemaining();
    return seconds === null ? "" : formatMMSS(seconds);
  });

  const ringOffset = createMemo(() => {
    const seconds = blackoutStore.secondsRemaining();
    const total = blackoutStore.totalDuration();
    if (seconds === null || total === null || total <= 0) return 0;
    const progress = Math.max(0, Math.min(1, seconds / total));
    return 100 - progress * 100;
  });

  return (
    <div class={styles.root}>
      <Show when={blackoutStore.secondsRemaining() !== null}>
        <div class={styles.vignette} />
      </Show>

      <Transition
        enterActiveClass={styles.cardEnterActive}
        exitActiveClass={styles.cardExitActive}
        enterClass={styles.cardEnterFrom}
        exitToClass={styles.cardExitTo}
      >
        <Show when={blackoutStore.secondsRemaining() !== null}>
          <div class={styles.card}>
            <div class={styles.ringWrap}>
              <svg width={RING_SIZE} height={RING_SIZE} class={styles.ring}>
                <rect
                  x={RING_INSET}
                  y={RING_INSET}
                  width={RING_SIZE - RING_STROKE}
                  height={RING_SIZE - RING_STROKE}
                  rx={RING_SIZE / 2 - RING_INSET}
                  fill="none"
                  stroke="rgba(255,255,255,0.12)"
                  stroke-width={RING_STROKE}
                />
                <rect
                  x={RING_INSET}
                  y={RING_INSET}
                  width={RING_SIZE - RING_STROKE}
                  height={RING_SIZE - RING_STROKE}
                  rx={RING_SIZE / 2 - RING_INSET}
                  fill="none"
                  stroke="var(--color-destructive)"
                  stroke-width={RING_STROKE}
                  stroke-linecap="butt"
                  pathLength={100}
                  stroke-dasharray="100"
                  stroke-dashoffset={ringOffset()}
                  class={styles.ringProgress}
                />
              </svg>
              <span class={styles.ringLabel}>{label()}</span>
            </div>

            <div class={styles.info}>
              <p class={styles.title}>{t()("blackout.title")}</p>
              <p class={styles.subtitle}>
                <Show when={blackoutStore.canSelfRevive()} fallback={t()("blackout.waitingForHelp")}>
                  {t()("blackout.selfReviveHint.before")} <span class={styles.key}>E</span> {t()("blackout.selfReviveHint.after")}
                </Show>
              </p>
            </div>
          </div>
        </Show>
      </Transition>
    </div>
  );
};
