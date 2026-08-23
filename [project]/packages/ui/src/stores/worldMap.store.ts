import { createStore, reconcile } from "solid-js/store";
import type { WorldMapPlayer, WorldMapSnapshot, WorldMapStore } from "@/types/worldMap";
import { mta } from "@/lib/mta/MtaBridge";

// createStore + reconcile(key) - same reasoning as scoreboard.store.ts's
// own comment: a plain createSignal<Array> plus mutated cached objects
// doesn't re-render <For>'s per-row JSX reads (a player's x/y as it
// moves), since Solid never notices a mutation on a plain object.
// reconcile keeps the same row/pin alive across refreshes instead of
// throwing the whole list away every WORLDMAP_DATA_RECEIVED.
const [players, setPlayers] = createStore<WorldMapPlayer[]>([]);
const [stores, setStores] = createStore<WorldMapStore[]>([]);

export const worldMapStore = {
  players: () => players,
  stores: () => stores,
};

mta.on("worldmap.data", (data) => {
  const snapshot = data as WorldMapSnapshot;
  setPlayers(reconcile(snapshot.players, { key: "id" }));
  setStores(reconcile(snapshot.stores, { key: "id" }));
});
