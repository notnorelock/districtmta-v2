import { createSignal } from "solid-js";
import { createStore, reconcile } from "solid-js/store";
import type { InventorySnapshot, InventoryItem } from "@/types/inventory";
import { mta } from "@/lib/mta/MtaBridge";

// createStore + reconcile (not createSignal<Array> + in-place mutation) -
// same reasoning scoreboard.store.ts's own module comment documents:
// a plain signal doesn't re-render fields <For>'s row JSX reads directly
// (amount, favorite, ...) when the underlying array is only mutated in
// place, since Solid never notices a plain property write on an object
// it isn't tracking. reconcile() diffs by `id`, keeping the same row/DOM
// node alive across a re-sync instead of throwing the whole list away.
const [items, setItems] = createStore<InventoryItem[]>([]);
const [weight, setWeight] = createSignal(0);
const [maxWeight, setMaxWeight] = createSignal(0);

function useItem(id: number) {
  mta.notify("inventory:useItem", id);
}

function dropItem(id: number) {
  mta.notify("inventory:dropItem", id);
}

function toggleFavorite(id: number) {
  mta.notify("inventory:toggleFavorite", id);
}

export const inventoryStore = {
  items: () => items,
  weight,
  maxWeight,
  useItem,
  dropItem,
  toggleFavorite,
};

mta.on("inventory.items", (data) => {
  const snapshot = data as InventorySnapshot;
  setItems(reconcile(snapshot.items, { key: "id" }));
  setWeight(snapshot.weight);
  setMaxWeight(snapshot.maxWeight);
});
