import { type Component, For, Show } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { Package } from "lucide-solid";
import { Marquee } from "@/components/common/Marquee";
import { itemToastStore } from "@/stores/itemToast.store";
import styles from "./ItemToast.module.scss";

// Above this length, even wrapped onto two lines a name like "Kluczyki do
// pojazdu" (20 chars, fits comfortably) starts running past the card's
// own w-28 - Marquee only kicks in past that point. Below it, the name
// just wraps onto its own two lines (styles.name's own line-clamp-2) with
// no animation at all - confirmed with the user: scroll-bouncing a name
// that only barely overflowed one line read as unnecessary/distracting,
// wrapping is legible on its own for anything this short.
const MARQUEE_THRESHOLD_CHARS = 32;

/**
 * Bottom-center "you gained/lost an item" toast stack, FiveM-style - a
 * small vertical card per item (big centered icon on top, name + amount
 * stacked below it, not an icon-beside-text row) laid out side by side as
 * more arrive. Always mounted (not gated behind any Overlay key, same
 * reasoning as DutyIndicator.tsx/GroupInviteToast.tsx), purely driven by
 * itemToast.store.ts, which ItemService.lua's own pickup/give/drop push
 * via Events.ITEM_TOAST feeds (see that file's own pushItemToast comment
 * on why "use" deliberately does NOT go through this - a used item
 * already has its own scheme-specific feedback, e.g. a lock toggle).
 * Replaces the plain native dxDraw NotificationService.send text those
 * three actions used to send - no icon-per-item-model system exists yet
 * (no world-object-model-to-CEF-image pipeline), so every card shares one
 * generic Package glyph rather than the item's own 3D model/icon.
 */
export const ItemToast: Component = () => {
  return (
    <div class={styles.dock}>
      <TransitionGroup
        enterActiveClass={styles.cardEnterActive}
        exitActiveClass={styles.cardExitActive}
        enterClass={styles.cardEnterFrom}
        exitToClass={styles.cardExitTo}
        moveClass={styles.cardMove}
      >
        <For each={itemToastStore.cards()}>
          {(card) => (
            <div class={`${styles.card} ${card.kind === "lost" ? styles.cardLost : styles.cardGained}`}>
              <div class={styles.icon}>
                <Package size={36} />
              </div>
              <Show
                when={card.schemeKey.length > MARQUEE_THRESHOLD_CHARS}
                fallback={<span class={styles.name}>{card.schemeKey}</span>}
              >
                <Marquee class={styles.nameMarquee} durationSeconds={4}>
                  {card.schemeKey}
                </Marquee>
              </Show>
              <span class={styles.amount}>
                {card.kind === "gained" ? "+" : "-"}
                {card.amount}
              </span>
            </div>
          )}
        </For>
      </TransitionGroup>
    </div>
  );
};
