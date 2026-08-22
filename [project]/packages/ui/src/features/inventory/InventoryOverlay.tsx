import { type Component, For, Show, createMemo, createSignal } from "solid-js";
import { Backpack, Fish, Key, Package, Play, Star, Trash2, Weight } from "lucide-solid";
import type { LucideProps } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/Tooltip";
import { inventoryStore } from "@/stores/inventory.store";
import { ITEM_SCHEME_CATEGORY, ItemCategory } from "@/types/inventory";
import type { InventoryItem } from "@/types/inventory";
import { t } from "@/i18n";
import styles from "./InventoryOverlay.module.scss";

type CategoryTab = ItemCategory | "all" | "favorites";

const CATEGORY_TABS: { id: CategoryTab; icon: Component<LucideProps>; labelKey: string }[] = [
  { id: "favorites", icon: Star, labelKey: "inventory.category.favorites" },
  { id: "all", icon: Backpack, labelKey: "inventory.category.all" },
  { id: ItemCategory.FOOD, icon: Fish, labelKey: "inventory.category.food" },
  { id: ItemCategory.KEYS, icon: Key, labelKey: "inventory.category.keys" },
  { id: ItemCategory.OTHER, icon: Package, labelKey: "inventory.category.other" },
];

interface ContextMenuState {
  item: InventoryItem;
  x: number;
  y: number;
}

/**
 * Inventory panel (I) - a plain toggle, non-blocking overlay
 * (gm_items/client/InventoryState.lua's own comment: movement keeps
 * working while open, right-click additionally locks controls and grabs
 * cursor focus to interact with the list/context menu), same pattern
 * ScoreboardOverlay.tsx already uses for TAB.
 *
 * Ported visually from an older, unrelated project's own dx-GUI
 * inventory (category tabs down the side, a scrollable list, a
 * left-click context menu with Użyj/Do ulubionych/Wyrzuć, a weight
 * footer) - rebuilt here in CEF/SolidJS rather than native dxDraw, and
 * WITHOUT that reference's own trading/fishing-rod-specific features
 * (no trade system, no job system exist in this project - see
 * gm_items/shared/ItemSchemes.lua's own module comment on scope). The
 * reference (and an earlier version of this file) opened the menu on
 * right-click, but that collides with InventoryState.lua's own
 * right-click cursor/focus toggle (both fire off the same physical
 * click) - left-click avoids that entirely.
 *
 * No existing context-menu/popover primitive exists anywhere in this
 * project's component library (checked before writing this) - the menu
 * below is a plain absolutely-positioned div at the click coordinates,
 * closed on any subsequent click elsewhere or Escape.
 */
export const InventoryOverlay: Component = () => {
  const [activeTab, setActiveTab] = createSignal<CategoryTab>("all");
  const [contextMenu, setContextMenu] = createSignal<ContextMenuState | null>(null);

  const visibleItems = createMemo(() => {
    const tab = activeTab();
    const all = inventoryStore.items();

    if (tab === "all") return all;
    if (tab === "favorites") return all.filter((item) => item.favorite);
    return all.filter((item) => (ITEM_SCHEME_CATEGORY[item.schemeKey] ?? ItemCategory.OTHER) === tab);
  });

  const openContextMenu = (event: MouseEvent, item: InventoryItem) => {
    event.preventDefault();
    event.stopPropagation();
    setContextMenu({ item, x: event.clientX, y: event.clientY });
  };

  const closeContextMenu = () => setContextMenu(null);

  const runAction = (action: (id: number) => void) => {
    const menu = contextMenu();
    if (!menu) return;
    action(menu.item.id);
    closeContextMenu();
  };

  return (
    <Overlay name="inventory" transitionName="inventory">
      <div class={styles.root} onClick={closeContextMenu}>
        <div class={styles.panel}>
          <div class={styles.tabs}>
            <For each={CATEGORY_TABS}>
              {(tab) => {
                const Icon = tab.icon;
                const active = () => activeTab() === tab.id;
                return (
                  <Tooltip placement="left">
                    <TooltipTrigger
                      as="button"
                      type="button"
                      class={`${styles.tab} ${active() ? styles.tabActive : ""}`}
                      onClick={() => setActiveTab(tab.id)}
                    >
                      <Icon size={18} />
                    </TooltipTrigger>
                    <TooltipContent>{t()(tab.labelKey)}</TooltipContent>
                  </Tooltip>
                );
              }}
            </For>
          </div>

          <div class={styles.main}>
            <div class={styles.header}>
              <span class={styles.title}>{t()(CATEGORY_TABS.find((tab) => tab.id === activeTab())?.labelKey ?? "inventory.category.all")}</span>
              <div class={styles.weight}>
                <Weight size={14} />
                <span>{inventoryStore.weight().toFixed(1)} / {inventoryStore.maxWeight().toFixed(1)} kg</span>
              </div>
            </div>

            <div class={styles.listWrap}>
              <For each={visibleItems()} fallback={<div class={styles.empty}>{t()("inventory.empty")}</div>}>
                {(item) => (
                  <div class={styles.row} onClick={(event: MouseEvent) => openContextMenu(event, item)}>
                    <div class={styles.rowIcon}>
                      <Package size={16} />
                    </div>
                    <span class={styles.rowName}>{item.schemeKey}</span>
                    <Show when={item.favorite}>
                      <Star size={13} class={styles.favoriteIcon} />
                    </Show>
                    <span class={styles.rowAmount}>x{item.amount}</span>
                  </div>
                )}
              </For>
            </div>

            <div class={styles.footer}>{t()("inventory.hint")}</div>
          </div>
        </div>

        <Show when={contextMenu()}>
          {(menu) => (
            <div
              class={styles.contextMenu}
              style={{ left: `${menu().x}px`, top: `${menu().y}px` }}
              onClick={(event) => event.stopPropagation()}
            >
              <button type="button" class={styles.contextItem} onClick={() => runAction(inventoryStore.useItem)}>
                <Play size={14} />
                {t()("inventory.action.use")}
              </button>
              <button
                type="button"
                class={styles.contextItem}
                onClick={() => runAction((id) => inventoryStore.toggleFavorite(id))}
              >
                <Star size={14} />
                {menu().item.favorite ? t()("inventory.action.unfavorite") : t()("inventory.action.favorite")}
              </button>
              <button type="button" class={`${styles.contextItem} ${styles.contextItemDanger}`} onClick={() => runAction(inventoryStore.dropItem)}>
                <Trash2 size={14} />
                {t()("inventory.action.drop")}
              </button>
            </div>
          )}
        </Show>
      </div>
    </Overlay>
  );
};
