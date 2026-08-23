import { createSignal } from "solid-js";
import { createStore, reconcile } from "solid-js/store";
import type { StoredVehicle, VehicleStorageSnapshot, VehicleStorePurpose } from "@/types/vehicleStorage";
import { mta } from "@/lib/mta/MtaBridge";

const [vehicles, setVehicles] = createStore<StoredVehicle[]>([]);
const [storeId, setStoreId] = createSignal<number | null>(null);
const [storeName, setStoreName] = createSignal("");
const [storePurpose, setStorePurpose] = createSignal<VehicleStorePurpose>("private");

function retrieveVehicle(id: number) {
  mta.notify("vehicles:storageRetrieve", id);
}

export const vehicleStorageStore = {
  vehicles: () => vehicles,
  storeId,
  storeName,
  storePurpose,
  retrieveVehicle,
};

// storeName/purpose only arrive on the FIRST push (VehicleStorageState.lua's
// own openStorage call) - wait, purpose is now re-sent on every refresh
// too (see that file's own comment) since a GROUP lot's own vehicle list
// can be empty-for-this-player, which storeName doesn't need but purpose
// does (nothing else in a later push would otherwise tell the panel it's
// still a group lot). storeName keeps its own "omitted on refresh, keep
// the prior value" behavior.
mta.on("vehicles.storageItems", (data) => {
  const snapshot = data as VehicleStorageSnapshot;
  setStoreId(snapshot.storeId);
  if (snapshot.storeName) {
    setStoreName(snapshot.storeName);
  }
  setStorePurpose(snapshot.purpose ?? "private");
  setVehicles(reconcile(snapshot.vehicles, { key: "id" }));
});
