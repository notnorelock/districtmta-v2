import { type Component, For } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { Package } from "lucide-solid";
import { itemToastStore } from "@/stores/itemToast.store";
import styles from "./ItemToast.module.scss";

/**
 * Bottom-center "you gained/lost an item" toast stack, FiveM-style -
 * always mounted (not gated behind any Overlay key, same reasoning as
 * DutyIndicator.tsx/GroupInviteToast.tsx), purely driven by
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
                <Package size={18} />
              </div>
              <div class={styles.info}>
                <span class={styles.name}>{card.schemeKey}</span>
              </div>
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
