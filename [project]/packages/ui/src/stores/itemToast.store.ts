import { createStore } from "solid-js/store";
import type { ItemToastCard, ItemToastEntry } from "@/types/itemToast";
import { mta } from "@/lib/mta/MtaBridge";

const TOAST_DURATION_MS = 4000;

const [cards, setCards] = createStore<ItemToastCard[]>([]);

let nextId = 0;

function remove(id: number) {
  setCards((current) => current.filter((card) => card.id !== id));
}

export const itemToastStore = {
  cards: () => cards,
};

mta.on("items.toast", (data) => {
  const entry = data as ItemToastEntry;
  const id = nextId++;
  setCards((current) => [...current, { ...entry, id }]);
  window.setTimeout(() => remove(id), TOAST_DURATION_MS);
});
