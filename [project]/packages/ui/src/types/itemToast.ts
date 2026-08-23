/** Mirrors ItemService.lua's own pushItemToast payload (Events.ITEM_TOAST/PUSH_ITEM_TOAST). */
export interface ItemToastEntry {
  kind: "gained" | "lost";
  schemeKey: string;
  amount: number;
}

/** One toast card as tracked client-side - adds a unique key so repeated pickups of the same item each get their own card/animation instead of colliding. */
export interface ItemToastCard extends ItemToastEntry {
  id: number;
}
