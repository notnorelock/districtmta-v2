/** One radial menu slice - id matches VehicleInteractionService.lua's `action` strings exactly for the four real ones; the rest are disabled placeholders (see VehicleMenuOverlay.tsx's own module comment). */
export type VehicleInteractionAction = "engine" | "lights" | "lock" | "handbrake" | "siren" | "horn" | "trunk";

export interface VehicleInteractionSlice {
  action: VehicleInteractionAction;
  /** False for slices with no backing system yet (siren/horn/trunk) - shown in the ring but not selectable. */
  enabled: boolean;
}

/** Mirrors VehicleInteractionService.lua's stateOf - always all four real keys present once known. */
export interface VehicleInteractionVehicleState {
  engine: boolean;
  lights: boolean;
  lock: boolean;
  /** setElementFrozen, not GTA's own space-bar handbrake - fully immobile, not just braked. See VehicleInteractionService.lua's own module comment. */
  handbrake: boolean;
}
