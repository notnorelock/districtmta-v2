import { createStore, reconcile } from "solid-js/store";
import type { ScoreboardPlayer } from "@/types/scoreboard";
import { mta } from "@/lib/mta/MtaBridge";

/**
 * Mirrors gm_scoreboard/server/ScoreboardService.lua's toEntry, as sent
 * over "scoreboard.players" - login/role/faction/nameColor are `false`
 * (Lua's nil can't cross exports.core_ui:uiPushEvent/a table field, same
 * convention used across this project's other push payloads) until the
 * player has actually authenticated, normalized to null here.
 */
interface ScoreboardPlayerPayload {
  id: number;
  name: string;
  login: string | false;
  role: number | false;
  faction: string | false;
  nameColor: string | false;
  status: ScoreboardPlayer["status"];
  ping: number;
}

// createStore (not createSignal<Array>), and reconcile (not a plain
// setter) - a plain createSignal<ScoreboardPlayer[]> plus mutating cached
// objects in place (the pattern voice.store.ts uses) does NOT re-render
// the fields <For>'s per-row JSX reads directly (player.status, .ping,
// etc.) - those are plain property reads on an object, not signals, so
// Solid never notices the mutation and the row's visible text goes stale
// until the whole row unmounts/remounts (e.g. closing and reopening the
// scoreboard, which throws the entire list away and rebuilds it). A
// solid-js/store IS fine-grained reactive per-field, and reconcile()
// diffs the incoming array against the existing store by `id` (see the
// key option below), updating only the fields that actually changed
// in place - keeping the same row/DOM node alive across refreshes
// (matches <For>'s own by-reference stability) while still making every
// field genuinely reactive.
const [players, setPlayers] = createStore<ScoreboardPlayer[]>([]);

export const scoreboardStore = {
  players: () => players,
};

mta.on("scoreboard.players", (data) => {
  const incoming = data as ScoreboardPlayerPayload[];

  const resolved: ScoreboardPlayer[] = incoming.map((entry) => ({
    id: entry.id,
    name: entry.name,
    login: entry.login === false ? null : entry.login,
    role: entry.role === false ? null : (entry.role as ScoreboardPlayer["role"]),
    faction: entry.faction === false ? null : entry.faction,
    nameColor: entry.nameColor === false ? null : entry.nameColor,
    status: entry.status,
    ping: entry.ping,
  }));

  setPlayers(reconcile(resolved, { key: "id" }));
});
