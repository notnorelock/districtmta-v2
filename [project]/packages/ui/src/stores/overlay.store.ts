import { createSignal } from "solid-js";
import { mta } from "@/lib/mta/MtaBridge";

// Mirrors BrowserManager.lua's visibleOverlays registry - separate from
// uiStore's activeWindow, and (by design) only ever mutated by Lua script
// code pushing overlay.show/overlay.hide, never by the browser itself.
const [visibleOverlays, setVisibleOverlays] = createSignal<ReadonlySet<string>>(new Set());

export const overlayStore = {
  isVisible: (name: string) => visibleOverlays().has(name),
};

mta.on("overlay.show", (data) => {
  if (typeof data !== "string") return;
  setVisibleOverlays((current) => new Set(current).add(data));
});

mta.on("overlay.hide", (data) => {
  if (typeof data !== "string") return;
  setVisibleOverlays((current) => {
    const next = new Set(current);
    next.delete(data);
    return next;
  });
});
