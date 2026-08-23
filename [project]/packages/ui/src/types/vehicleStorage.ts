/** Mirrors VehicleStorageService.lua's own toEntry - one vehicle sitting in the currently-open storage lot. */
export interface StoredVehicle {
  id: number;
  model: number;
  name: string;
  mileage: number;
  plate: string | null;
  /** False for a vehicle owned by someone else - only ever present here at all because the requesting player carries a VEHICLE_KEY item for it (see VehicleStorageService.lua's own playerHasKeyTo). */
  owned: boolean;
}

/** Mirrors Enums.VehicleStorePurpose in core_shared/shared/Enums.lua. */
export type VehicleStorePurpose = "private" | "group";

/** Mirrors VehicleStorageState.lua's own PUSH_VEHICLE_STORAGE_ITEMS payload shape. */
export interface VehicleStorageSnapshot {
  storeId: number;
  storeName?: string;
  /** Absent only on a pre-existing push that predates this field - treat as "private" if so. */
  purpose?: VehicleStorePurpose;
  vehicles: StoredVehicle[];
}
