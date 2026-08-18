import { For, Show, createSignal, onMount, type Component } from "solid-js";
import { Button } from "@/components/ui/Button";
import { spawnApi } from "@/lib/api/spawnApi";
import type { SpawnLocation } from "@/types/spawn";
import { t } from "@/i18n";

/** Spawn selection screen, shown after the auth window closes. */
export const SpawnSelectView: Component = () => {
  const [locations, setLocations] = createSignal<SpawnLocation[]>([]);
  const [loading, setLoading] = createSignal(true);
  const [selectingId, setSelectingId] = createSignal<string | null>(null);
  const [entering, setEntering] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const loadLocations = async () => {
    setLoading(true);
    setError(null);
    const response = await spawnApi.list();

    if (!response.success) {
      setError(t()(`auth.error.${response.error.code}`));
      setLoading(false);
      return;
    }

    setLocations(response.data);
    setLoading(false);
  };

  onMount(loadLocations);

  const handleSelect = async (location: SpawnLocation) => {
    if (selectingId()) return;

    setSelectingId(location.id);
    setError(null);
    const response = await spawnApi.select(location.id);

    if (!response.success) {
      setError(t()(`auth.error.${response.error.code}`));
      setSelectingId(null);
      return;
    }

    // Window close is delayed until the player actually spawns - see AuthUiClient.lua.
    setEntering(true);
  };

  return (
    <div class="flex h-full w-full flex-col items-center justify-center gap-10 bg-black px-6 font-display">
      <Show
        when={!entering()}
        fallback={
          <div class="flex flex-col items-center gap-4 text-center">
            <span class="h-8 w-8 animate-spin rounded-full border-2 border-accent-indigo border-t-transparent" />
            <p class="text-sm text-muted-foreground">{t()("spawn.entering")}</p>
          </div>
        }
      >
        <div class="text-center">
          <h1 class="text-2xl font-bold uppercase tracking-wide text-foreground">{t()("spawn.title")}</h1>
          <p class="mt-1 text-sm text-muted-foreground">{t()("spawn.subtitle")}</p>
        </div>

        <Show when={loading()}>
          <span class="h-8 w-8 animate-spin rounded-full border-2 border-accent-indigo border-t-transparent" />
        </Show>

        <Show when={error()}>
          <p class="text-sm text-danger">{error()}</p>
        </Show>

        <Show when={!loading()}>
          <div class="grid w-full max-w-3xl grid-cols-1 gap-4 sm:grid-cols-2">
            <For each={locations()}>
              {(location) => (
                <div class="flex flex-col justify-between gap-4 rounded-xl border border-accent-indigo/20 bg-accent-indigo/10 p-5 backdrop-blur-md">
                  <div>
                    <h2 class="text-base font-bold text-foreground">{location.name}</h2>
                    <p class="mt-1 text-sm text-muted-foreground">{location.description}</p>
                  </div>

                  <Button
                    type="button"
                    variant="gradient"
                    class="h-auto w-full rounded-xl py-3 text-xs font-bold uppercase tracking-widest"
                    loading={selectingId() === location.id}
                    disabled={selectingId() !== null}
                    onClick={() => void handleSelect(location)}
                  >
                    {t()("spawn.select")}
                  </Button>
                </div>
              )}
            </For>
          </div>
        </Show>
      </Show>
    </div>
  );
};
