/** Mirrors WorldMapService.lua's toPlayerEntry. */
export interface WorldMapPlayer {
  id: number;
  name: string;
  x: number;
  y: number;
  z: number;
}

/** Mirrors WorldMapService.lua's toStoreEntry. */
export interface WorldMapStore {
  id: number;
  name: string;
  x: number;
  y: number;
}

/** Mirrors the { players, stores } payload sent over "worldmap.data". */
export interface WorldMapSnapshot {
  players: WorldMapPlayer[];
  stores: WorldMapStore[];
}
