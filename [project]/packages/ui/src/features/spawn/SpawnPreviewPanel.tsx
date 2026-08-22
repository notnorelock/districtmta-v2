import type { Component } from "solid-js";
import { Button } from "@/components/ui/Button";
import type { MapPin } from "@/components/common/Map2D";
import { t } from "@/i18n";
import styles from "./SpawnPreviewPanel.module.scss";

interface SpawnPreviewPanelProps {
  pin: MapPin;
  /** Pin's current on-canvas position, in screen pixels - from Map2D's onSelectedPinScreenPos - so this card stays anchored to it as the map is panned/zoomed. */
  anchor: { x: number; y: number } | null;
  confirming: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

/**
 * Small confirmation card anchored to the clicked pin's own on-canvas
 * position (see props.anchor) - name/description plus a "Wybierz"
 * button that actually commits to spawnApi.select. No preview render of
 * any kind; a 3D camera preview here was tried (a live orbiting camera,
 * then a pre-rendered panorama strip) and dropped - picking a spawn just
 * needs the confirm step, not a look around first.
 */
export const SpawnPreviewPanel: Component<SpawnPreviewPanelProps> = (props) => {
  return (
    <div
      class={styles.root}
      style={props.anchor ? { left: `${props.anchor.x}px`, top: `${props.anchor.y}px` } : { display: "none" }}
    >
      <div class={styles.card}>
        <button type="button" class={styles.closeButton} onClick={props.onCancel} disabled={props.confirming} aria-label={t()("spawn.previewCancel")}>
          ×
        </button>

        <div class={styles.info}>
          <h2 class={styles.title}>{props.pin.label}</h2>
          {props.pin.description && <p class={styles.description}>{props.pin.description}</p>}
        </div>

        <Button type="button" variant="gradient" class={styles.confirmButton} loading={props.confirming} onClick={props.onConfirm}>
          {t()("spawn.select")}
        </Button>
      </div>
    </div>
  );
};
