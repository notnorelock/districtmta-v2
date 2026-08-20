/** Mirrors InteractionRegistry.lua's definitions - icon is an "IconXxx" name matched client-side against @tabler/icons-solidjs (see WorldInteractionOverlay.tsx's ICON map). */
export interface WorldInteractionItem {
  key: string;
  label: string;
  icon: string;
}

/** Mirrors WorldInteractionState.lua's PUSH_INTERACTION_TARGET payload - the target element's current screen position. */
export interface WorldInteractionTarget {
  x: number;
  y: number;
}
