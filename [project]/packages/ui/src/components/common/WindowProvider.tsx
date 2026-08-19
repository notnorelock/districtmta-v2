import { createContext, useContext, type FlowComponent } from "solid-js";
import { uiStore } from "@/stores/ui.store";

export interface WindowContextValue {
  /** The single named CEF window Lua currently wants open (UI.open/close), or null. */
  activeWindow: () => string | null;
  /** False until the first ui.open push arrives - see ui.store.ts's own comment. */
  hasOpenedAnyWindow: () => boolean;
}

const WindowContext = createContext<WindowContextValue>();

/**
 * Wraps the tree in access to the active-window state. uiStore itself
 * stays the single subscriber to the underlying ui.open/ui.close push
 * events (module-level, so it only subscribes once no matter how many
 * times a provider mounts) - this just exposes that state through
 * context, same pattern as OverlayProvider/useOverlay.
 */
export const WindowProvider: FlowComponent = (props) => {
  return <WindowContext.Provider value={uiStore}>{props.children}</WindowContext.Provider>;
};

/** @throws if used outside a WindowProvider */
export function useWindow(): WindowContextValue {
  const context = useContext(WindowContext);
  if (!context) {
    throw new Error("useWindow must be used within a WindowProvider");
  }
  return context;
}
