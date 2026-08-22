/** Mirrors SpawnLocations.toPublicList() in core_auth/server/SpawnLocations.lua. */
export interface SpawnLocation {
  id: string;
  name: string;
  description: string;
  /** GTA:SA world coordinates - same values used to actually spawn the player, see gameplayEnterWorld. Used to place a pin on Map2D. */
  x: number;
  y: number;
}

export interface SelectSpawnResult {
  id: string;
}
