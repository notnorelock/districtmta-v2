import { createSignal } from "solid-js";
import type { ScoreboardPlayer } from "@/types/scoreboard";
import { mta } from "@/lib/mta/MtaBridge";

/**
 * Mirrors gm_scoreboard/server/ScoreboardService.lua's toEntry, as sent
 * over "scoreboard.players" - login/role/faction are `false` (Lua's nil
 * can't cross exports.core_ui:uiPushEvent/a table field, same convention
 * used across this project's other push payloads) until the player has
 * actually authenticated, normalized to null here.
 */
interface ScoreboardPlayerPayload {
  id: number;
  name: string;
  login: string | false;
  role: number | false;
  faction: string | false;
  status: ScoreboardPlayer["status"];
  ping: number;
}

// Lua sends a brand-new table per player on every push (each request/
// response round trip rebuilds the whole list from scratch) - SolidJS's
// <For> keys by object identity, not value, so without this a full
// re-request every refresh interval would read as "every row left and a
// new one arrived", causing flicker. Same fix as voice.store.ts: cache by
// a stable key (id, not name - a player's account login already exists as
// a more stable choice, but id is always present even before login exists)
// and mutate the cached object in place instead of replacing it.
const playerObjectsById = new Map<number, ScoreboardPlayer>();

const [players, setPlayers] = createSignal<ScoreboardPlayer[]>([]);

export const scoreboardStore = {
  players,
};

mta.on("scoreboard.players", (data) => {
  const incoming = data as ScoreboardPlayerPayload[];
  const incomingIds = new Set(incoming.map((entry) => entry.id));

  for (const id of playerObjectsById.keys()) {
    if (!incomingIds.has(id)) {
      playerObjectsById.delete(id);
    }
  }

  const resolved = incoming.map((entry) => {
    const normalized: ScoreboardPlayer = {
      id: entry.id,
      name: entry.name,
      login: entry.login === false ? null : entry.login,
      role: entry.role === false ? null : (entry.role as ScoreboardPlayer["role"]),
      faction: entry.faction === false ? null : entry.faction,
      status: entry.status,
      ping: entry.ping,
    };

    const existing = playerObjectsById.get(entry.id);
    if (existing) {
      Object.assign(existing, normalized);
      return existing;
    }

    playerObjectsById.set(entry.id, normalized);
    return normalized;
  });

  setPlayers(resolved);
});
