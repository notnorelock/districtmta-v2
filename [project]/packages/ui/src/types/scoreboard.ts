import type { AccountRole } from "@/types/account";

/** Mirrors ScoreboardService.Status in gm_scoreboard/server/ScoreboardService.lua. */
export const ScoreboardStatus = {
  DOWNLOADING: "downloading",
  AUTHENTICATING: "authenticating",
  SELECTING_SPAWN: "selectingSpawn",
  IN_GAME: "inGame",
} as const;

export type ScoreboardStatus = (typeof ScoreboardStatus)[keyof typeof ScoreboardStatus];

/** Mirrors ScoreboardService.lua's toEntry - login/role/faction/nameColor are null until authenticated (Lua sends false, normalized to null here, see scoreboard.store.ts). */
export interface ScoreboardPlayer {
  id: number;
  name: string;
  login: string | null;
  role: AccountRole | null;
  /** Group name if currently on GROUP duty (gang/organization/fraction), null otherwise - see ScoreboardService.lua's own groupDutyNameOf. */
  faction: string | null;
  /** #RRGGBB from getPlayerNametagColor - null while unauthenticated (before PlayerService.refreshNametagColor has ever run for this player). */
  nameColor: string | null;
  status: ScoreboardStatus;
  ping: number;
}
