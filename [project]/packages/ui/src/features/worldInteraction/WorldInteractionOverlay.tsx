import { type Component, For, Show, createMemo, createSignal, createEffect } from "solid-js";
import {
  IconTool,
  IconRotate,
  IconArrowBackUp,
  IconHandGrab,
  IconLock,
  IconQuestionMark,
  IconMouse2,
  IconSpace,
  type IconProps,
} from "@tabler/icons-solidjs";
import { Overlay } from "@/components/common/Overlay";
import { worldInteractionStore } from "@/stores/worldInteraction.store";
import { t } from "@/i18n";
import styles from "./WorldInteractionOverlay.module.scss";

type IconComponent = Component<IconProps>;

/**
 * Maps InteractionRegistry.lua's `icon` field ("IconXxx" names) to the
 * actual @tabler/icons-solidjs component - kept as an explicit map rather
 * than a dynamic `(Icons as any)[name]` lookup (the reference
 * implementation's own approach, in React) since that defeats
 * TypeScript/webpack's static analysis entirely; a name with no entry
 * here falls back to IconQuestionMark instead of rendering nothing, so a
 * future interaction added server-side without updating this map is
 * still visible (just generically iconed) rather than silently blank.
 */
const ICONS: Record<string, IconComponent> = {
  IconTool,
  IconRotate,
  IconArrowBackUp,
  IconHandGrab,
  IconLock,
};

/**
 * World interaction: E toggles a WallShader outline on nearby elements
 * (gm_interactions/client/WorldInteractionState.lua) - no cursor at all,
 * whichever outlined element is closest to the CENTER OF THE SCREEN (i.e.
 * whatever you're actually looking at) becomes the active target
 * automatically. Ported visually from an older, unrelated project's own
 * "world interaction" UI (a vignette + a dashed line and rotating diamond
 * pointing at the target + a vertical option list that slides to keep the
 * selected item centered) rather than this project's other menus' own
 * look, per explicit user request - colors/fonts still follow this
 * project's own tokens (--color-primary etc., font-display) instead of
 * the reference's plain white/dark palette.
 *
 * Entirely scroll/space-driven, same reasoning as VehicleMenuOverlay.tsx -
 * no click/hover handlers on the list items (there's no cursor to click
 * with here). The bottom hint uses icons (scroll wheel, space bar) rather
 * than describing the controls in words alone, same pattern
 * VehicleMenuOverlay's own controlsBar uses.
 */
export const WorldInteractionOverlay: Component = () => {
  const hasTarget = createMemo(() => worldInteractionStore.target() !== null);
  const hasItems = createMemo(() => worldInteractionStore.items().length > 0);

  const target = createMemo(() => worldInteractionStore.target() ?? { x: 0, y: 0 });

  // The line's end point is measured from the ACTIVE item's own real DOM
  // position (left edge, vertical center) rather than a fixed "50% of
  // screen" guess - .list's CSS transition means the active item's Y
  // keeps moving for 0.15s after selectedIndex changes, so this re-reads
  // getBoundingClientRect on every animation frame while the list is
  // showing, not just once on change. itemEls is keyed by index rather
  // than a single "current active element" signal - <For> reuses the
  // same DOM nodes across a selectedIndex change (it doesn't remount),
  // so each item's own ref only fires once per node, not every time its
  // active() state changes; reading itemEls[selectedIndex()] inside
  // measure() (which re-runs every frame) is what actually stays current.
  const itemEls: (HTMLDivElement | undefined)[] = [];
  const [lineEnd, setLineEnd] = createSignal({ x: 0, y: 0 });

  createEffect(() => {
    if (!hasItems()) {
      return;
    }

    let raf = 0;
    const measure = () => {
      const el = itemEls[worldInteractionStore.selectedIndex()];
      if (el) {
        const rect = el.getBoundingClientRect();
        setLineEnd({ x: rect.left, y: rect.top + rect.height / 2 });
      }
      raf = requestAnimationFrame(measure);
    };
    raf = requestAnimationFrame(measure);

    return () => cancelAnimationFrame(raf);
  });

  return (
    <Overlay name="worldInteraction" transitionName="worldInteraction">
      <div class={styles.root}>
        <div class={styles.vignette} />

        <Show when={hasTarget() && hasItems()}>
          {/* Points at the active list item's own real left-edge/
              vertical-center DOM position (see lineEnd above), not a
              fixed screen-center guess - stays correct regardless of
              where the list/target actually sit on screen. */}
          <svg width="100vw" height="100vh" class={styles.pointerLine} aria-hidden="true">
            <line
              x1={target().x}
              y1={target().y}
              x2={lineEnd().x}
              y2={lineEnd().y}
              class={styles.pointerLineStroke}
            />
          </svg>

          <div
            class={styles.pointerDiamond}
            style={{ left: `${target().x}px`, top: `${target().y}px` }}
            aria-hidden="true"
          />
        </Show>

        <Show when={hasItems()}>
          <div class={styles.list} style={{ "--selected-index": worldInteractionStore.selectedIndex() }}>
            <For each={worldInteractionStore.items()}>
              {(item, index) => {
                const Icon = ICONS[item.icon] ?? IconQuestionMark;
                const active = () => worldInteractionStore.selectedIndex() === index();
                return (
                  <div
                    class={`${styles.item} ${active() ? styles.itemActive : ""}`}
                    ref={(el) => {
                      itemEls[index()] = el;
                    }}
                  >
                    <span class={styles.itemIcon}>
                      <Icon size={16} stroke="1.8" />
                    </span>
                    <span>{item.label}</span>
                  </div>
                );
              }}
            </For>
          </div>
        </Show>

        <div class={styles.hint}>
          <h3>{t()("worldInteraction.title")}</h3>
          <div class={styles.controlsBar}>
            <div class={styles.controlHint}>
              <IconMouse2 size={18} stroke="1.7" />
              <span>{t()("worldInteraction.scrollHint")}</span>
            </div>
            <div class={styles.controlHint}>
              <IconSpace size={18} stroke="1.7" />
              <span>{t()("worldInteraction.spaceHint")}</span>
            </div>
          </div>
        </div>
      </div>
    </Overlay>
  );
};
