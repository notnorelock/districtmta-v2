import { createSignal } from "solid-js";
import { mta } from "@/lib/mta/MtaBridge";
import type { VehicleInteractionAction, VehicleInteractionSlice, VehicleInteractionVehicleState } from "@/types/vehicleInteraction";

/**
 * 7-slice ring, based on the reference screenshot's 6-slice layout plus
 * one extra (handbrake) - engine/lights/lock/handbrake are real
 * (VehicleInteractionService.lua actually handles them); siren/horn/trunk
 * have no backing system in this project (no emergency-vehicle siren
 * system, no horn-sound wiring beyond GTA's own default, no trunk/boot
 * open state tracked anywhere) and are shown disabled rather than
 * omitted, so the ring still reads as a real menu without pretending
 * those three features work - see VehicleMenuOverlay.tsx's own module
 * comment. Angular spacing is computed from SLICES.length, so adding
 * this 7th slice didn't need any layout changes.
 */
const SLICES: VehicleInteractionSlice[] = [
  { action: "engine", enabled: true },
  { action: "lights", enabled: true },
  { action: "siren", enabled: false },
  { action: "lock", enabled: true },
  { action: "handbrake", enabled: true },
  { action: "horn", enabled: false },
  { action: "trunk", enabled: false },
];

const FIRST_ENABLED_INDEX = SLICES.findIndex((slice) => slice.enabled);

/** Mirrors VehicleInteractionService.lua's PUSH_VEHICLE_INTERACTION_STATE payload - action is false for the initial "just opened, here's current state" push (no action just happened). */
interface InteractionStatePayload {
  action: VehicleInteractionAction | false;
  state: VehicleInteractionVehicleState;
}

const [selectedIndex, setSelectedIndex] = createSignal(FIRST_ENABLED_INDEX);
const [vehicleState, setVehicleState] = createSignal<VehicleInteractionVehicleState | null>(null);

function moveSelection(forward: boolean) {
  const count = SLICES.length;
  let index = selectedIndex();

  for (let attempt = 0; attempt < count; attempt++) {
    index = ((forward ? index + 1 : index - 1) + count) % count;
    if (SLICES[index]?.enabled) {
      setSelectedIndex(index);
      return;
    }
  }
}

function activateSelection() {
  const slice = SLICES[selectedIndex()];
  if (!slice || !slice.enabled) {
    return;
  }
  mta.notify("vehicles:interactionActivated", slice.action);
}

export const vehicleInteractionStore = {
  slices: SLICES,
  selectedIndex,
  vehicleState,
};

mta.on("vehicles.interactionScroll", (data) => {
  moveSelection(data === true);
});

mta.on("vehicles.interactionActivate", () => {
  activateSelection();
});

mta.on("vehicles.interactionState", (data) => {
  const payload = data as InteractionStatePayload;
  setVehicleState(payload.state);
});
