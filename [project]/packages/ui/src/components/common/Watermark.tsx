import { Show, type Component } from "solid-js";
import { useOverlay } from "@/components/common/OverlayProvider";

/**
 * Bottom-left server watermark. Uses its own "watermark" overlay key
 * (see ui_hud/client/HudState.lua) - shown once the player first spawns,
 * independent of the "hud" overlay HudBar uses, so anything that later
 * hides/shows just the HUD doesn't affect this. No enter/leave transition
 * here (unlike HudBar's <Overlay>) - just a plain <Show>.
 */
export const Watermark: Component = () => {
  const overlay = useOverlay();

  return (
    <Show when={overlay.isVisible("watermark")}>
      <div class="pointer-events-none fixed bottom-4 left-4 z-40 select-none font-display text-xs tracking-wide text-muted-foreground/70">
        districtmta.pl - indev ({__BUILD_COMMIT__})
      </div>
    </Show>
  );
};
