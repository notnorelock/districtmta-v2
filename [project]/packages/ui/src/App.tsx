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
        <HudBar />
      </Overlay>

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
