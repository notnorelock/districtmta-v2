import { mta } from "@/lib/mta/MtaBridge";
import type { MtaResponse } from "@/types/api";
import type { SelectSpawnResult, SpawnLocation } from "@/types/spawn";

// Typed wrapper over the spawn.* FetchBridge endpoints - same convention as authApi.
export const spawnApi = {
  list(): Promise<MtaResponse<SpawnLocation[]>> {
    return mta.fetch<SpawnLocation[]>("spawn.list", []);
  },

  select(id: string): Promise<MtaResponse<SelectSpawnResult>> {
    return mta.fetch<SelectSpawnResult>("spawn.select", [{ id }]);
  },
};
