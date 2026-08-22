import { createSignal } from "solid-js";
import { createStore, reconcile } from "solid-js/store";
import type { StoredVehicle, VehicleStorageSnapshot } from "@/types/vehicleStorage";
import { mta } from "@/lib/mta/MtaBridge";

const [vehicles, setVehicles] = createStore<StoredVehicle[]>([]);
const [storeId, setStoreId] = createSignal<number | null>(null);
const [storeName, setStoreName] = createSignal("");

function retrieveVehicle(id: number) {
  mta.notify("vehicles:storageRetrieve", id);
}

export const vehicleStorageStore = {
  vehicles: () => vehicles,
  storeId,
  storeName,
  retrieveVehicle,
};

// storeName only arrives on the FIRST push (VehicleStorageState.lua's own
// openStorage call) - a later refresh (sendStoreItems after a retrieve)
// omits it, see PUSH_VEHICLE_STORAGE_ITEMS's own Lua-side comment. Keep
// whatever name is already known rather than clobbering it with undefined.
mta.on("vehicles.storageItems", (data) => {
  const snapshot = data as VehicleStorageSnapshot;
  setStoreId(snapshot.storeId);
  if (snapshot.storeName) {
    setStoreName(snapshot.storeName);
  }
  setVehicles(reconcile(snapshot.vehicles, { key: "id" }));
});
