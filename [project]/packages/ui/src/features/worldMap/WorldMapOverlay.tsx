import { type Component, createMemo, createSignal } from "solid-js";
import { Users, Warehouse } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { Map2D, type MapPin } from "@/components/common/Map2D";
import { t } from "@/i18n";
import { worldMapStore } from "@/stores/worldMap.store";
import styles from "./WorldMapOverlay.module.scss";

const PLAYER_COLOR = "#3dd68c";
const STORE_COLOR = "#f2b84b";

type LegendCategory = "players" | "stores";

/**
 * F11 world map/legend - full-screen, toggled open/closed by
 * WorldMapState.lua, own "worldMap" overlay key (Overlay name prop).
 *
 * Layout mirrors AuthCard.tsx's own left-column + right-content split
 * (no SmokeBackground here though - deliberately left out for this
 * overlay) rather than a floating legend card over the map - a fixed
 * max-w-md sidebar holding the title and the legend, map filling the
 * remaining width. Every online player's live
 * position plus static points of interest (currently just vehicle
 * storage lots) plot on the map; either category can be hidden
 * independently from the sidebar rather than a single-select filter,
 * since a player might want both on screen together. The legend list is
 * keyed by category so a future point-of-interest type (shops, police
 * stations, etc. - see the old reference implementation's much longer
 * blip list) only needs a new LEGEND_ITEMS entry, not a layout change.
 */
export const WorldMapOverlay: Component = () => {
  const [hiddenCategories, setHiddenCategories] = createSignal<Set<LegendCategory>>(new Set());

  const toggleCategory = (category: LegendCategory) => {
    setHiddenCategories((current) => {
      const next = new Set(current);
      if (next.has(category)) {
        next.delete(category);
      } else {
        next.add(category);
      }
      return next;
    });
  };

  const pins = createMemo<MapPin[]>(() => {
    const hidden = hiddenCategories();
    const result: MapPin[] = [];

    if (!hidden.has("players")) {
      for (const player of worldMapStore.players()) {
        result.push({ id: `player:${player.id}`, x: player.x, y: player.y, label: player.name, color: PLAYER_COLOR });
      }
    }

    if (!hidden.has("stores")) {
      for (const store of worldMapStore.stores()) {
        result.push({ id: `store:${store.id}`, x: store.x, y: store.y, label: store.name, color: STORE_COLOR });
      }
    }

    return result;
  });

  return (
    <Overlay name="worldMap" transitionName="worldMap">
      <div class={styles.root}>
        <div class={styles.sidebar}>
          <div class={styles.sidebarContent}>
            <div>
              <h1 class={styles.title}>{t()("worldMap.title")}</h1>
              <p class={styles.subtitle}>{t()("worldMap.subtitle")}</p>
            </div>

            <div class={styles.legend}>
              <span class={styles.legendHeading}>{t()("worldMap.legend.heading")}</span>

              <button
                type="button"
                class={`${styles.legendItem} ${hiddenCategories().has("players") ? styles.legendItemDimmed : ""}`}
                onClick={() => toggleCategory("players")}
              >
                <Users size={16} style={{ color: PLAYER_COLOR }} />
                <span class={styles.legendLabel}>{t()("worldMap.legend.players")}</span>
                <span class={styles.legendCount}>{worldMapStore.players().length}</span>
              </button>

              <button
                type="button"
                class={`${styles.legendItem} ${hiddenCategories().has("stores") ? styles.legendItemDimmed : ""}`}
                onClick={() => toggleCategory("stores")}
              >
                <Warehouse size={16} style={{ color: STORE_COLOR }} />
                <span class={styles.legendLabel}>{t()("worldMap.legend.stores")}</span>
                <span class={styles.legendCount}>{worldMapStore.stores().length}</span>
              </button>
            </div>

            <div class={styles.controls}>
              <span class={styles.controlsHeading}>{t()("worldMap.controls.heading")}</span>
              <p class={styles.controlsText}>{t()("worldMap.controls.text")}</p>
            </div>

            <span class={styles.closeHint}>{t()("worldMap.closeHint")}</span>
          </div>
        </div>

        <div class={styles.mapWrap}>
          <Map2D class={styles.map} pins={pins()} minZoom={0.75} maxZoom={6} />
        </div>
      </div>
    </Overlay>
  );
};
