import { onMount, Match, Switch, type Component } from "solid-js";
import { ErrorScreen } from "@/components/common/ErrorScreen";
import { LoginView } from "@/features/auth/LoginView";
import { SpawnSelectView } from "@/features/spawn/SpawnSelectView";
import { ResourceCheckScreen } from "@/features/loading/ResourceCheckScreen";
import { ToastStack } from "@/features/notifications/ToastStack";
import { authStore } from "@/stores/auth.store";
import { uiStore } from "@/stores/ui.store";
import { mta } from "@/lib/mta/MtaBridge";
import "@/styles/globals.css";

const App: Component = () => {
  onMount(() => {
    console.log("[App] mounted, checking auth status and notifying ui.ready");
    void authStore.checkStatus();
    mta.notify("ui.ready");
  });

  return (
    <div class="h-full w-full">
      <Switch>
        <Match when={authStore.phase() === "error"}>
          <ErrorScreen onRetry={() => void authStore.checkStatus()} />
        </Match>
        <Match when={authStore.phase() === "checking" || (!uiStore.hasOpenedAnyWindow() && uiStore.activeWindow() === null)}>
          {/* activeWindow() check avoids a blank screen if auth.status resolves before
              LOADING_READY; hasOpenedAnyWindow() avoids re-showing this after spawn. */}
          <ResourceCheckScreen />
        </Match>
        <Match when={authStore.phase() === "unauthenticated" && uiStore.activeWindow() === "authentication"}>
          <LoginView />
        </Match>
        <Match when={authStore.phase() === "authenticated" && uiStore.activeWindow() === "spawnSelect"}>
          <SpawnSelectView />
        </Match>
      </Switch>

      <ToastStack />
    </div>
  );
};

export default App;
