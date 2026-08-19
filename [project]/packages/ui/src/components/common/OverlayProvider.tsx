import { createContext, useContext, type FlowComponent } from "solid-js";
import { overlayStore } from "@/stores/overlay.store";

export interface OverlayContextValue {
  /** True if `name` is currently visible - script(Lua)-driven, see overlay.store.ts. */
  isVisible: (name: string) => boolean;
}

const OverlayContext = createContext<OverlayContextValue>();

/**
 * Wraps the tree in access to overlay visibility state. overlayStore
 * itself stays the single subscriber to the underlying overlay.show/
 * overlay.hide push events (module-level, so it only subscribes once no
 * matter how many times a provider mounts) - this just exposes that
 * state through context instead of every consumer importing the store
 * module directly, so a future overlay root (e.g. one scoped to a
 * specific feature tree) has a seam to provide a different value.
 */
export const OverlayProvider: FlowComponent = (props) => {
  return <OverlayContext.Provider value={overlayStore}>{props.children}</OverlayContext.Provider>;
};

/** @throws if used outside an OverlayProvider */
export function useOverlay(): OverlayContextValue {
  const context = useContext(OverlayContext);
  if (!context) {
    throw new Error("useOverlay must be used within an OverlayProvider");
  }
  return context;
}
