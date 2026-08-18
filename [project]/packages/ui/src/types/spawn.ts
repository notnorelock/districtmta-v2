/** Mirrors SpawnLocations.toPublicList() in core_auth/server/SpawnLocations.lua. */
export interface SpawnLocation {
  id: string;
  name: string;
  description: string;
}

export interface SelectSpawnResult {
  id: string;
}
