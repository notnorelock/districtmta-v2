import { Show, createMemo, createSignal, onMount, type Component } from "solid-js";
import { Map2D, type MapPin } from "@/components/common/Map2D";
import { SpawnPreviewPanel } from "./SpawnPreviewPanel";
import { SmokeBackground } from "@/components/common/SmokeBackground";
import { spawnApi } from "@/lib/api/spawnApi";
import type { SpawnLocation } from "@/types/spawn";
import { t } from "@/i18n";

function toPin(location: SpawnLocation): MapPin {
  return { id: location.id, x: location.x, y: location.y, label: location.name, description: location.description };
}

/** Spawn selection screen, shown after the auth window closes - a clickable Map2D pin per SpawnLocations.lua entry. Clicking a pin opens SpawnPreviewPanel, a small confirmation card anchored to it, with the actual spawnApi.select commit gated behind its own "Wybierz" button. */
export const SpawnSelectView: Component = () => {
  const [locations, setLocations] = createSignal<SpawnLocation[]>([]);
  const [loading, setLoading] = createSignal(true);
  const [previewingId, setPreviewingId] = createSignal<string | null>(null);
  const [previewAnchor, setPreviewAnchor] = createSignal<{ x: number; y: number } | null>(null);
  const [focusTarget, setFocusTarget] = createSignal<{ x: number; y: number; zoom?: number } | null>(null);
  const [selectingId, setSelectingId] = createSignal<string | null>(null);
  const [entering, setEntering] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  // Zoom level a pin is brought to when clicked - close enough to read as
  // "zoomed in on this spot" without needing to also know Map2D's own
  // max zoom.
  const PIN_FOCUS_ZOOM = 2.5;

  const previewingLocation = createMemo(() => locations().find((location) => location.id === previewingId()) ?? null);

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

  const handleConfirm = async (location: SpawnLocation) => {
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
    <div class="relative h-full w-full bg-black font-display">
      <Show
        when={!entering()}
        fallback={
          <div class="flex h-full w-full flex-col items-center justify-center gap-4 text-center">
            <span class="h-8 w-8 animate-spin rounded-full border-2 border-accent-indigo border-t-transparent" />
            <p class="text-sm text-muted-foreground">{t()("spawn.entering")}</p>
          </div>
        }
      >
        <Show
          when={!loading()}
          fallback={
            <div class="flex h-full w-full items-center justify-center">
              <span class="h-8 w-8 animate-spin rounded-full border-2 border-accent-indigo border-t-transparent" />
            </div>
          }
        >
          {/* Map fills the whole window - title/subtitle/error float over
              it as their own layer rather than sharing a centered flex
              column with it, so the map always gets the full viewport
              regardless of how much header content there is. */}
          <Map2D
            class="h-full w-full rounded-none border-none"
            pins={locations().map(toPin)}
            onPinClick={(pin) => {
              setPreviewingId(pin.id);
              // A fresh object every click (not just when x/y differ) -
              // clicking the same already-focused pin again should still
              // re-trigger Map2D's focus effect rather than being a no-op.
              setFocusTarget({ x: pin.x, y: pin.y, zoom: PIN_FOCUS_ZOOM });
            }}
            selectedPinId={previewingId()}
            onSelectedPinScreenPos={setPreviewAnchor}
            focusTarget={focusTarget()}
          />

          {/* Same atmospheric smoke as the login screen (AuthCard.tsx),
              but transparent - AuthCard.tsx renders it on an opaque black
              WebGL background, which would have blacked out the map
              entirely sitting on top of it here. */}
          <SmokeBackground transparent color="#ffffff" opacity={0.2} enableWind enableTurbulence />

          <div class="pointer-events-none absolute inset-x-0 top-0 flex flex-col items-center gap-1 p-6 text-center">
            <h1 class="text-2xl font-bold tracking-tight text-foreground [text-shadow:0_2px_8px_rgb(0_0_0/0.8)]">{t()("spawn.title")}</h1>
            <p class="text-sm text-muted-foreground [text-shadow:0_2px_8px_rgb(0_0_0/0.8)]">{t()("spawn.subtitle")}</p>

            <Show when={error()}>
              <p class="mt-2 text-sm text-danger">{error()}</p>
            </Show>
          </div>

          <Show when={previewingLocation()} keyed>
            {(location) => (
              <SpawnPreviewPanel
                pin={toPin(location)}
                anchor={previewAnchor()}
                confirming={selectingId() === location.id}
                onConfirm={() => void handleConfirm(location)}
                onCancel={() => setPreviewingId(null)}
              />
            )}
          </Show>
        </Show>
      </Show>
    </div>
  );
};
