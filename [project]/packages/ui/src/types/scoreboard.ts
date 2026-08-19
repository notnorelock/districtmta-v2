import type { AccountRole } from "@/types/account";

/** Mirrors ScoreboardService.Status in gm_scoreboard/server/ScoreboardService.lua. */
export const ScoreboardStatus = {
  DOWNLOADING: "downloading",
  AUTHENTICATING: "authenticating",
  SELECTING_SPAWN: "selectingSpawn",
  IN_GAME: "inGame",
} as const;

export type ScoreboardStatus = (typeof ScoreboardStatus)[keyof typeof ScoreboardStatus];

/** Mirrors ScoreboardService.lua's toEntry - login/role/faction are null until authenticated (Lua sends false, normalized to null here, see scoreboard.store.ts). */
export interface ScoreboardPlayer {
  id: number;
  name: string;
  login: string | null;
  role: AccountRole | null;
  /** No faction/group system exists yet in this project - always null today, a placeholder column until one does. */
  faction: string | null;
  status: ScoreboardStatus;
  ping: number;
}
