import { createSignal } from "solid-js";
import { mta, isMtaEnvironment } from "@/lib/mta/MtaBridge";

// Mirrors which single named CEF window Lua wants open (core_ui/client/ui/BrowserManager.lua).
const [activeWindow, setActiveWindow] = createSignal<string | null>(
  // Outside MTA, default to the auth screen since no push event will ever arrive.
  isMtaEnvironment() ? null : "authentication",
);

// Distinguishes "nothing opened yet" (show loading screen) from "a window opened and
// closed" (show nothing) - both look like activeWindow() === null otherwise, which left
// App.tsx stuck showing "Loading..." after every spawn.
const [hasOpenedAnyWindow, setHasOpenedAnyWindow] = createSignal(!isMtaEnvironment());

export const uiStore = {
  activeWindow,
  hasOpenedAnyWindow,
};

mta.on("ui.open", (data) => {
  if (typeof data !== "string") return;
  setActiveWindow(data);
  setHasOpenedAnyWindow(true);
});

// Only clear activeWindow if it's still the one being closed - a stale close push (e.g.
// "authentication" arriving after spawnSelect already opened, two unordered handlers
// racing off the same event) would otherwise wipe out the window that's actually open.
mta.on("ui.close", (data) => {
  const closingWindow = typeof data === "string" ? data : null;
  setActiveWindow((current) => (closingWindow === null || current === closingWindow ? null : current));
});
