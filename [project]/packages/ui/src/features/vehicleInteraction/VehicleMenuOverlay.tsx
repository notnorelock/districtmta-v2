import { type Component, For, Show, createMemo } from "solid-js";
import {
  IconBulb,
  IconBulbFilled,
  IconLock,
  IconLockOpen,
  IconEngine,
  IconEngineFilled,
  IconParkingCircle,
  IconParkingCircleFilled,
  IconSpeakerphone,
  IconVolume2,
  IconPackage,
  type IconProps,
} from "@tabler/icons-solidjs";
import { Overlay } from "@/components/common/Overlay";
import { vehicleInteractionStore } from "@/stores/vehicleInteraction.store";
import type { VehicleInteractionAction } from "@/types/vehicleInteraction";
import { t } from "@/i18n";
import styles from "./VehicleMenuOverlay.module.scss";

const RING_SIZE = 460;
const RING_RADIUS = 190;
const DECOR_RADIUS = 216;
const ICON_RADIUS = 162;
const LABEL_RADIUS = 222;

type IconComponent = Component<IconProps>;

/** Off/on icon pairs - the filled variant reads as "engaged" at a glance, same idea as a pressed toggle button. */
const SLICE_ICON: Record<VehicleInteractionAction, { off: IconComponent; on: IconComponent }> = {
  engine: { off: IconEngine, on: IconEngineFilled },
  lights: { off: IconBulb, on: IconBulbFilled },
  lock: { off: IconLockOpen, on: IconLock },
  handbrake: { off: IconParkingCircle, on: IconParkingCircleFilled },
  siren: { off: IconSpeakerphone, on: IconSpeakerphone },
  horn: { off: IconVolume2, on: IconVolume2 },
  trunk: { off: IconPackage, on: IconPackage },
};

const SLICE_LABEL_KEY: Record<VehicleInteractionAction, string> = {
  engine: "vehicleMenu.engine",
  lights: "vehicleMenu.lights",
  lock: "vehicleMenu.lock",
  handbrake: "vehicleMenu.handbrake",
  siren: "vehicleMenu.siren",
  horn: "vehicleMenu.horn",
  trunk: "vehicleMenu.trunk",
};

const DECOR_DOT_COUNT = 36;

/**
 * Radial vehicle interaction menu - hold left Shift while driving to show
 * it (gm_vehicles_interaction/client/VehicleInteractionState.lua), scroll
 * to move the selection around the ring, space to activate. Deliberately
 * no cursor/click interaction at all - see VehicleInteractionState.lua's
 * own module comment on why (this project's gm_scoreboard right-click
 * saga: guiSetInputEnabled fighting bindKey's own held-state tracking),
 * scroll wheel and space are both already free while driving.
 *
 * Icons are @tabler/icons-solidjs, not lucide-solid (the rest of this
 * project's icon set) - a deliberate one-off swap for this menu only,
 * picked for its off/on "outline vs filled" icon pairs (IconBulb/
 * IconBulbFilled etc.), which read as a toggle state at a glance in a way
 * a single fixed icon can't. A slowly-spinning ring of decorative dots
 * behind the main ring, a glowing/pulsing halo under the selected slice,
 * and a spring-eased (cubic-bezier overshoot, not linear) selection
 * indicator replace the earlier flatter/static version per user request
 * ("zrób coś z zajebistymi animacjami"). Colors stay this project's own
 * warm primary/accent-violet gradient, not the original reference
 * screenshot's blue/pink, for consistency with the rest of the UI.
 *
 * Only engine/lights/lock/handbrake are real
 * (gm_vehicles_interaction/server/VehicleInteractionService.lua) - siren/
 * horn/trunk are shown as disabled slices (not omitted) so the ring still
 * reads as a complete menu without pretending those three features work
 * - see vehicleInteraction.store.ts's own module comment.
 */
export const VehicleMenuOverlay: Component = () => {
  const selectedSlice = createMemo(() => vehicleInteractionStore.slices[vehicleInteractionStore.selectedIndex()]);

  const sliceAngle = (index: number) => (360 / vehicleInteractionStore.slices.length) * index - 90;
  const ringOffset = createMemo(() => sliceAngle(vehicleInteractionStore.selectedIndex()));

  const isOn = (action: VehicleInteractionAction) => {
    const state = vehicleInteractionStore.vehicleState();
    if (!state) return false;
    if (action === "engine") return state.engine;
    if (action === "lights") return state.lights;
    if (action === "lock") return state.lock;
    if (action === "handbrake") return state.handbrake;
    return false;
  };

  return (
    <Overlay name="vehicleInteraction" transitionName="vehicleMenu">
      <div class={styles.root}>
        <div class={styles.backdrop} />
        <div class={styles.ringWrap} style={{ width: `${RING_SIZE}px`, height: `${RING_SIZE}px` }}>
          <div class={styles.glow} />

          {/* Purely decorative, slowly-spinning dot ring behind everything else - gives the whole menu a sense of motion even while the selection sits still. */}
          <div class={styles.decorRing} aria-hidden="true">
            <For each={Array.from({ length: DECOR_DOT_COUNT })}>
              {(_, index) => {
                const angle = (360 / DECOR_DOT_COUNT) * index();
                const rad = (angle * Math.PI) / 180;
                const x = RING_SIZE / 2 + Math.cos(rad) * DECOR_RADIUS;
                const y = RING_SIZE / 2 + Math.sin(rad) * DECOR_RADIUS;
                return <span class={styles.decorDot} style={{ left: `${x}px`, top: `${y}px` }} />;
              }}
            </For>
          </div>

          <svg width={RING_SIZE} height={RING_SIZE} class={styles.ring} viewBox={`0 0 ${RING_SIZE} ${RING_SIZE}`}>
            <defs>
              <linearGradient id="vehicleMenuGradient" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="var(--color-accent-indigo)" />
                <stop offset="50%" stop-color="var(--color-primary)" />
                <stop offset="100%" stop-color="var(--color-accent-violet)" />
              </linearGradient>
              <filter id="vehicleMenuGlow" x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="4" result="blur" />
                <feMerge>
                  <feMergeNode in="blur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>
            <circle cx={RING_SIZE / 2} cy={RING_SIZE / 2} r={RING_RADIUS} class={styles.ringTrack} />
            <g
              class={styles.ringIndicatorGroup}
              style={{ transform: `rotate(${ringOffset()}deg)`, "transform-origin": `${RING_SIZE / 2}px ${RING_SIZE / 2}px` }}
            >
              <circle
                cx={RING_SIZE / 2}
                cy={RING_SIZE / 2}
                r={RING_RADIUS}
                class={styles.ringIndicator}
                pathLength={100}
                stroke-dasharray={`${100 / vehicleInteractionStore.slices.length} 100`}
                filter="url(#vehicleMenuGlow)"
              />
            </g>
          </svg>

          <For each={vehicleInteractionStore.slices}>
            {(slice, index) => {
              const angleDeg = () => sliceAngle(index());
              const angleRad = () => (angleDeg() * Math.PI) / 180;
              const x = () => RING_SIZE / 2 + Math.cos(angleRad()) * ICON_RADIUS;
              const y = () => RING_SIZE / 2 + Math.sin(angleRad()) * ICON_RADIUS;
              // Label sits further out along the same radius, on the
              // OUTSIDE of the ring - so it reads next to its icon
              // without overlapping the ring stroke or neighboring
              // slices. Anchored left/right/center depending on which
              // side of the circle it's on, so text always grows away
              // from the ring instead of getting clipped under it.
              const labelX = () => RING_SIZE / 2 + Math.cos(angleRad()) * LABEL_RADIUS;
              const labelY = () => RING_SIZE / 2 + Math.sin(angleRad()) * LABEL_RADIUS;
              const labelAnchor = () => {
                const cos = Math.cos(angleRad());
                if (cos > 0.35) return styles.labelLeft;
                if (cos < -0.35) return styles.labelRight;
                return styles.labelCenter;
              };
              const icons = SLICE_ICON[slice.action];
              const selected = () => vehicleInteractionStore.selectedIndex() === index();

              return (
                <>
                  <div
                    class={`${styles.slice} ${selected() ? styles.sliceSelected : ""} ${!slice.enabled ? styles.sliceDisabled : ""} ${isOn(slice.action) ? styles.sliceOn : ""}`}
                    style={{ left: `${x()}px`, top: `${y()}px` }}
                  >
                    <span class={styles.sliceHalo} />
                    <Show when={isOn(slice.action)} fallback={<icons.off size={30} stroke="1.7" />}>
                      <icons.on size={30} stroke="1.7" />
                    </Show>
                  </div>
                  <span
                    class={`${styles.sliceLabel} ${labelAnchor()} ${selected() ? styles.sliceLabelSelected : ""} ${!slice.enabled ? styles.sliceLabelDisabled : ""}`}
                    style={{ left: `${labelX()}px`, top: `${labelY()}px` }}
                  >
                    {t()(SLICE_LABEL_KEY[slice.action])}
                  </span>
                </>
              );
            }}
          </For>

          <div class={styles.center}>
            <div class={styles.centerRing} />
            <Show when={selectedSlice()} keyed>
              {(slice) => (
                <div class={styles.centerContent}>
                  <p class={styles.centerTitle}>{t()(SLICE_LABEL_KEY[slice.action])}</p>
                  <Show
                    when={slice.enabled}
                    fallback={<p class={styles.centerHint}>{t()("vehicleMenu.unavailable")}</p>}
                  >
                    <p class={`${styles.centerState} ${isOn(slice.action) ? styles.centerStateOn : ""}`}>
                      <span class={styles.centerStateDot} />
                      {isOn(slice.action) ? t()("vehicleMenu.on") : t()("vehicleMenu.off")}
                    </p>
                    <p class={styles.centerHint}>{t()("vehicleMenu.activateHint")}</p>
                  </Show>
                </div>
              )}
            </Show>
          </div>
        </div>
      </div>
    </Overlay>
  );
};
