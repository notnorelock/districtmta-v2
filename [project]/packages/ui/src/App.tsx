import { onMount, Match, Switch, type Component } from "solid-js";
import { ErrorScreen } from "@/components/common/ErrorScreen";
import { Overlay } from "@/components/common/Overlay";
import { OverlayProvider } from "@/components/common/OverlayProvider";
import { WindowProvider, useWindow } from "@/components/common/WindowProvider";
import { LoginView } from "@/features/auth/LoginView";
import { SpawnSelectView } from "@/features/spawn/SpawnSelectView";
import { ResourceCheckScreen } from "@/features/loading/ResourceCheckScreen";
import { ToastStack } from "@/features/notifications/ToastStack";
import { HudBar } from "@/features/hud/HudBar";
import { VoiceIndicator } from "@/features/hud/VoiceIndicator";
import { RadioCard } from "@/features/hud/RadioCard";
import { BlackoutOverlay } from "@/features/blackout/BlackoutOverlay";
import { ScoreboardOverlay } from "@/features/scoreboard/ScoreboardOverlay";
import { VehicleMenuOverlay } from "@/features/vehicleInteraction/VehicleMenuOverlay";
import { Watermark } from "@/components/common/Watermark";
import { authStore } from "@/stores/auth.store";
import { mta } from "@/lib/mta/MtaBridge";
import "@/styles/globals.css";

const AppContent: Component = () => {
  const windowState = useWindow();

  return (
    <div class="h-full w-full">
      <Switch>
        <Match when={authStore.phase() === "error"}>
          <ErrorScreen onRetry={() => void authStore.checkStatus()} />
        </Match>
        <Match when={authStore.phase() === "checking" || (!windowState.hasOpenedAnyWindow() && windowState.activeWindow() === null)}>
          {/* activeWindow() check avoids a blank screen if auth.status resolves before
              LOADING_READY; hasOpenedAnyWindow() avoids re-showing this after spawn. */}
          <ResourceCheckScreen />
        </Match>
        <Match when={authStore.phase() === "unauthenticated" && windowState.activeWindow() === "authentication"}>
          <LoginView />
        </Match>
        <Match when={authStore.phase() === "authenticated" && windowState.activeWindow() === "spawnSelect"}>
          <SpawnSelectView />
        </Match>
      </Switch>

      <Overlay name="hud" transitionName="hud">
        {/* fixed + inset-0, not a plain block div - HudBar/VoiceIndicator
            are both independently `fixed` already, but THIS wrapper is
            what .hud-enter-from/.hud-exit-to's translateX(48px) actually
            animates (see globals.css). A plain block div sits in normal
            flow at full body width, so translating IT right pushed its
            own box past the viewport edge and forced document.body's
            horizontal scrollbar to appear - fixed+inset-0 takes it out of
            flow entirely, so the transform only moves this (invisible,
            pointer-events-none) box, never the page's scrollable width. */}
        <div class="pointer-events-none fixed inset-0">
          <HudBar />
          <VoiceIndicator />
        </div>
      </Overlay>

      <Watermark />
      {/* Not gated behind the "hud" overlay - the radio card is its own
          independent system (gm_radio, not ui_hud) and should show even
          if the HUD itself is hidden, same reasoning as Watermark. */}
      <RadioCard />
      {/* Uses its own "blackout" overlay key internally (Overlay name
          prop) - rendered unconditionally here so it can show up
          regardless of auth/HUD state, same reasoning as Watermark/RadioCard. */}
      <BlackoutOverlay />
      {/* Uses its own "scoreboard" overlay key (Overlay name prop),
          toggled by gm_scoreboard while TAB is held - see
          ScoreboardOverlay.tsx's own comment. */}
      <ScoreboardOverlay />
      {/* Uses its own "vehicleInteraction" overlay key (Overlay name
          prop), shown by gm_vehicles while left Shift is held and driving
          - see VehicleMenuOverlay.tsx's own comment. */}
      <VehicleMenuOverlay />
      <ToastStack />
    </div>
  );
};

const App: Component = () => {
  onMount(() => {
    console.log("[App] mounted, checking auth status and notifying ui.ready");
    void authStore.checkStatus();
    mta.notify("ui.ready");
  });

  return (
    <WindowProvider>
      <OverlayProvider>
        <AppContent />
      </OverlayProvider>
    </WindowProvider>
  );
};

export default App;
