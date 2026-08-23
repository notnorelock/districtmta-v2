import { type Component, For, Show, createMemo, createSignal } from "solid-js";
import { Car, Gauge, Hash, KeyRound, Warehouse } from "lucide-solid";
import type { LucideProps } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/Tooltip";
import { vehicleStorageStore } from "@/stores/vehicleStorage.store";
import { t } from "@/i18n";
import styles from "./VehicleStorageOverlay.module.scss";

type CategoryTab = "all" | "owned" | "shared";

const CATEGORY_TABS: { id: CategoryTab; icon: Component<LucideProps>; labelKey: string }[] = [
  { id: "all", icon: Warehouse, labelKey: "vehicleStorage.category.all" },
  { id: "owned", icon: Car, labelKey: "vehicleStorage.category.owned" },
  { id: "shared", icon: KeyRound, labelKey: "vehicleStorage.category.shared" },
];

/**
 * Vehicle storage lot panel - opened/closed entirely by server/client Lua
 * (VehicleStorageState.lua's own VEHICLE_STORAGE_OPEN/CLOSE handlers, see
 * that file's own module comment), NOT a keybind toggle like Inventory/
 * Scoreboard - a player only ever sees this while standing inside a
 * storage lot's enter marker. Same non-blocking overlay + right-click
 * cursor/focus toggle pattern those two already use.
 *
 * Side category rail mirrors InventoryOverlay.tsx's own pattern - "Moje
 * pojazdy" (owned) vs "Udostępnione" (shared, i.e. someone else's vehicle
 * you're carrying a VEHICLE_KEY item for - see VehicleStorageService.lua's
 * own playerHasKeyTo). A borrowed vehicle only ever appears in this list
 * at all because the server already filtered it in for exactly that
 * reason, so every non-owned entry here is shared by definition.
 *
 * The entire rail is hidden for a GROUP-purpose lot (not just
 * "Udostępnione") - "owned"/"shared" are PRIVATE-lot-only concepts
 * (VEHICLE_KEY doesn't exist for group vehicles; every vehicle inside a
 * group lot already reports `owned: true` regardless of who's actually
 * driving it home, see VehicleStorageService.lua's own group-purpose
 * sendStoreItems branch), so "Moje pojazdy" there would just be a
 * confusing synonym for "Wszystkie" - the whole distinction the rail
 * exists to draw doesn't apply, so the rail itself doesn't either.
 *
 * Retrieving a vehicle is a click here (VEHICLE_STORAGE_RETRIEVE,
 * server re-validates ownership/key possession/lot membership - see
 * VehicleStorageService.lua). Storing a vehicle has no button/keypress at
 * all: driving your own private vehicle onto the lot's SEPARATE
 * store_position zone stores it immediately, server-side
 * (VehicleStorageService.lua's onStoreZoneHit/tryStoreVehicle) - this
 * panel only ever shows the "how" as a hint, never a store action, since
 * a store action here couldn't know which vehicle you're driving anyway.
 */
export const VehicleStorageOverlay: Component = () => {
  const [activeTab, setActiveTab] = createSignal<CategoryTab>("all");

  const isGroupLot = createMemo(() => vehicleStorageStore.storePurpose() === "group");

  const visibleVehicles = createMemo(() => {
    const all = vehicleStorageStore.vehicles();
    // No owned/shared distinction for a group lot - always the full list.
    if (isGroupLot()) return all;

    const tab = activeTab();
    if (tab === "all") return all;
    if (tab === "owned") return all.filter((vehicle) => vehicle.owned);
    return all.filter((vehicle) => !vehicle.owned);
  });

  return (
    <Overlay name="vehicleStorage" transitionName="vehicleStorage">
      <div class={styles.root}>
        <div class={styles.panel}>
          <Show when={!isGroupLot()}>
            <div class={styles.tabs}>
              <For each={CATEGORY_TABS}>
                {(tab) => {
                  const Icon = tab.icon;
                  const active = () => activeTab() === tab.id;
                  return (
                    <Tooltip placement="left">
                      <TooltipTrigger
                        as="button"
                        type="button"
                        class={`${styles.tab} ${active() ? styles.tabActive : ""}`}
                        onClick={() => setActiveTab(tab.id)}
                      >
                        <Icon size={18} />
                      </TooltipTrigger>
                      <TooltipContent>{t()(tab.labelKey)}</TooltipContent>
                    </Tooltip>
                  );
                }}
              </For>
            </div>
          </Show>

          <div class={styles.main}>
            <div class={styles.header}>
              <span class={styles.title}>{vehicleStorageStore.storeName() || t()("vehicleStorage.title")}</span>
            </div>

            <div class={styles.listWrap}>
              <For each={visibleVehicles()} fallback={<div class={styles.empty}>{t()("vehicleStorage.empty")}</div>}>
                {(vehicle) => (
                  <button
                    type="button"
                    class={styles.row}
                    onClick={() => vehicleStorageStore.retrieveVehicle(vehicle.id)}
                  >
                    <div class={styles.rowIcon}>
                      <Car size={16} />
                    </div>
                    <div class={styles.rowInfo}>
                      <span class={styles.rowName}>
                        {vehicle.name}
                        <Show when={!vehicle.owned}>
                          <Tooltip placement="top" openDelay={300}>
                            <TooltipTrigger as="span" class={styles.sharedIconTrigger}>
                              <KeyRound size={12} class={styles.sharedIcon} />
                            </TooltipTrigger>
                            <TooltipContent>{t()("vehicleStorage.sharedHint")}</TooltipContent>
                          </Tooltip>
                        </Show>
                      </span>
                      <div class={styles.rowMeta}>
                        <span class={styles.rowMetaItem}>
                          <Gauge size={12} />
                          {vehicle.mileage} km
                        </span>
                        <Show when={vehicle.plate}>
                          <span class={styles.rowMetaItem}>
                            <Hash size={12} />
                            {vehicle.plate}
                          </span>
                        </Show>
                      </div>
                    </div>
                    <span class={styles.rowAction}>{t()("vehicleStorage.action.retrieve")}</span>
                  </button>
                )}
              </For>
            </div>

            <div class={styles.footer}>
              <div>{t()("vehicleStorage.hint.retrieve")}</div>
              <div>{t()("vehicleStorage.hint.store")}</div>
            </div>
          </div>
        </div>
      </div>
    </Overlay>
  );
};
