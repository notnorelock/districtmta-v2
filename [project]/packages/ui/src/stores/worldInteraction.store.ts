import { createSignal } from "solid-js";
import { mta } from "@/lib/mta/MtaBridge";
import type { WorldInteractionItem, WorldInteractionTarget } from "@/types/worldInteraction";

const [items, setItems] = createSignal<WorldInteractionItem[]>([]);
const [selectedIndex, setSelectedIndex] = createSignal(0);
const [target, setTarget] = createSignal<WorldInteractionTarget | null>(null);

function moveSelection(direction: number) {
  const count = items().length;
  if (count === 0) {
    return;
  }
  setSelectedIndex((index) => (index + direction + count) % count);
}

function activateSelection() {
  const item = items()[selectedIndex()];
  if (!item) {
    return;
  }
  mta.notify("interactions:activated", item.key);
}

export const worldInteractionStore = {
  items,
  selectedIndex,
  target,
  activateSelection,
};

mta.on("interactions.list", (data) => {
  const incoming = data as WorldInteractionItem[];
  setItems(incoming);
  setSelectedIndex(0);
});

mta.on("interactions.navigate", (data) => {
  moveSelection(data as number);
});

mta.on("interactions.activate", () => {
  activateSelection();
});

mta.on("interactions.target", (data) => {
  setTarget(data as WorldInteractionTarget);
});
