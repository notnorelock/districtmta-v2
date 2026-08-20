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
  IconMouse2,
  IconSpace,
  type IconProps,
} from "@tabler/icons-solidjs";
import { Overlay } from "@/components/common/Overlay";
import { vehicleInteractionStore } from "@/stores/vehicleInteraction.store";
import type { VehicleInteractionAction } from "@/types/vehicleInteraction";
import { t } from "@/i18n";
import styles from "./VehicleMenuOverlay.module.scss";

const RING_SIZE = 460;
const DECOR_RADIUS = 216;
const ICON_RADIUS = 162;
// Sits just outside .centerRing's own edge (.center is size-44 = 176px,
// so an 88px radius) rather than out near the buttons - pointing right
// at the center text/label instead of floating in the button ring.
const POINTER_RADIUS = 96;

const SLICE_SCALE_SELECTED = 1.35;
const SLICE_SCALE_SELECTED_DISABLED = 1.1;

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

  // Rotates the pointer arrow (a fixed shape at 0deg/"up") around the
  // ring's own center to sit over whichever slice is selected - since
  // it rotates about the same center the slices are laid out on, it
  // stays radius-accurate at every angle without per-slice position math.
  const pointerAngle = createMemo(() => sliceAngle(vehicleInteractionStore.selectedIndex()) + 90);

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

          <div class={styles.ringSurface} />

          {/* Points from the ring's center toward whichever slice is
              selected - a single rotated shape instead of a per-slice arc,
              so "which button am I on" stays readable independent of the
              buttons' own (separately-animated) scale transition below. */}
          <div
            class={styles.pointer}
            style={{ transform: `translate(-50%, -50%) rotate(${pointerAngle()}deg) translateY(-${POINTER_RADIUS}px)` }}
          />

          <For each={vehicleInteractionStore.slices}>
            {(slice, index) => {
              const angleDeg = () => sliceAngle(index());
              const angleRad = () => (angleDeg() * Math.PI) / 180;
              const x = () => RING_SIZE / 2 + Math.cos(angleRad()) * ICON_RADIUS;
              const y = () => RING_SIZE / 2 + Math.sin(angleRad()) * ICON_RADIUS;
              const icons = SLICE_ICON[slice.action];
              const selected = () => vehicleInteractionStore.selectedIndex() === index();

              // Full transform computed here (translate for centering +
              // scale for the selected/disabled states) instead of split
              // across .slice/.sliceSelected/.sliceDisabled classes -
              // each of those was its own `transform:` shorthand rule, so
              // whichever one's CSS came out last in the stylesheet fully
              // overwrote the others instead of composing, which is why
              // the scale never actually animated smoothly.
              const scale = () => {
                if (!selected()) return 1;
                return slice.enabled ? SLICE_SCALE_SELECTED : SLICE_SCALE_SELECTED_DISABLED;
              };

              return (
                <div
                  class={`${styles.slice} ${selected() ? styles.sliceSelected : ""} ${!slice.enabled ? styles.sliceDisabled : ""} ${isOn(slice.action) ? styles.sliceOn : ""}`}
                  style={{ left: `${x()}px`, top: `${y()}px`, transform: `translate(-50%, -50%) scale(${scale()})` }}
                >
                  <span class={styles.sliceHalo} />
                  <Show when={isOn(slice.action)} fallback={<icons.off size={30} stroke="1.7" />}>
                    <icons.on size={30} stroke="1.7" />
                  </Show>
                </div>
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
                  </Show>
                </div>
              )}
            </Show>
          </div>
        </div>

        {/* Control hints moved out of the per-slice center panel (see
            this file's own module comment) - a fixed bar instead of text
            that changed/reflowed under every slice selection, with an
            icon for each input (scroll wheel to move the selection,
            space bar to activate it) instead of describing them in
            words alone. */}
        <div class={styles.controlsBar}>
          <div class={styles.controlHint}>
            <IconMouse2 size={18} stroke="1.7" />
            <span>{t()("vehicleMenu.scrollHint")}</span>
          </div>
          <div class={styles.controlHint}>
            <IconSpace size={18} stroke="1.7" />
            <span>{t()("vehicleMenu.spaceHint")}</span>
          </div>
        </div>
      </div>
    </Overlay>
  );
};
