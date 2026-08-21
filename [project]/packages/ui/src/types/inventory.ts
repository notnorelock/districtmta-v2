/** Mirrors Enums.ItemCategory in core_shared/shared/Enums.lua. */
export const ItemCategory = {
  FOOD: "food",
  KEYS: "keys",
  WEAPON: "weapon",
  OTHER: "other",
} as const;

export type ItemCategory = (typeof ItemCategory)[keyof typeof ItemCategory];

/**
 * Mirrors gm_items/shared/ItemSchemes.lua's own category field per scheme
 * key - the panel needs to know each item's category to filter by tab,
 * but the server only ever sends the item's own instance data (id,
 * amount, ...), never the scheme metadata itself (see
 * InventoryOverlay.tsx's own module comment on why: scheme data is
 * static/code-defined, not per-instance, so re-sending it on every push
 * would be pure waste - this file mirrors just the piece the UI needs,
 * the same convention ScoreboardOverlay.tsx's ROLE_LABEL already follows
 * for Permissions.colorForRole). Keep in sync by hand when
 * ItemSchemes.lua changes.
 */
export const ITEM_SCHEME_CATEGORY: Record<string, ItemCategory> = {
  "Mała ryba": ItemCategory.FOOD,
  "Średnia ryba": ItemCategory.FOOD,
  "Duża ryba": ItemCategory.FOOD,
  "Kluczyki do pojazdu": ItemCategory.KEYS,
};

/** Mirrors ItemService.lua's toEntry/itemFromRow - favorite/itemValues/flags are always present (never false-sentinel, unlike some other push payloads - see inventory.store.ts). */
export interface InventoryItem {
  id: number;
  schemeKey: string;
  amount: number;
  itemValues: unknown[];
  flags: string[];
  favorite: boolean;
}

/** Mirrors ItemService.lua's sync payload shape - { items, weight, maxWeight }. */
export interface InventorySnapshot {
  items: InventoryItem[];
  weight: number;
  maxWeight: number;
}
