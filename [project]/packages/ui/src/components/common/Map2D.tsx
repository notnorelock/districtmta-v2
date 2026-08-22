import { Show, createEffect, createSignal, onCleanup, onMount, type Component } from "solid-js";
import mapTextureUrl from "@/assets/textures/map.png";
import { cn } from "@/lib/cn";
import styles from "./Map2D.module.scss";

/**
 * A GTA:SA-coordinate pin to draw on the map - world x/y match whatever
 * the server already uses to place/spawn things (see SpawnLocations.lua),
 * so callers never need to convert coordinates themselves.
 */
export interface MapPin {
  id: string;
  x: number;
  y: number;
  label: string;
  description?: string;
  color?: string;
}

interface Map2DProps {
  pins: MapPin[];
  onPinClick?: (pin: MapPin) => void;
  /** Disables pin hover/click entirely - for a future read-only F11 world map/legend that reuses this same component. */
  interactive?: boolean;
  class?: string;
  minZoom?: number;
  maxZoom?: number;
  initialZoom?: number;
  /** When set, onSelectedPinScreenPos fires every redraw with that pin's current on-canvas position - lets a caller (SpawnPreviewPanel) anchor a floating panel to a pin that moves under drag/zoom instead of drawing at a fixed screen position. */
  selectedPinId?: string | null;
  onSelectedPinScreenPos?: (pos: { x: number; y: number } | null) => void;
  /** Set (a new object identity each time - see the effect that watches it) to smoothly pan/zoom the map onto a world position, e.g. centering on a pin the moment it's clicked. Uses the same eased startAnimating() a drag-release or wheel-zoom does, just driven externally instead of by pointer input. */
  focusTarget?: { x: number; y: number; zoom?: number } | null;
}

// GTA:SA world coordinates span roughly -3000..3000 on both axes - the
// same /6000 normalization the original dx-drawn map reference used, kept
// here so any x/y already used elsewhere in the codebase (spawn points,
// blips, vehicle store positions) plots correctly without a separate
// conversion table.
const WORLD_SIZE = 6000;

// Not 0 - a min zoom of 0 makes the map shrink toward nothing near the
// bottom of the range instead of stopping at "the whole map is visible",
// so scrolling further down just reads as "zoom stopped responding" once
// it's already too small to see any change. 0.5 keeps "fully zoomed out"
// at a size that's still clearly a map.
const DEFAULT_MIN_ZOOM = 0.5;
const DEFAULT_MAX_ZOOM = 4;
const ZOOM_WHEEL_SENSITIVITY = 0.010;
const PIN_RADIUS_PX = 7;
const PIN_HOVER_RADIUS_PX = 10;

// Both pan and zoom settle into their target value over this many ms
// instead of snapping - drag/wheel input still updates the target
// immediately (feels responsive), only the rendered value eases toward
// it every frame. Same easing curve for both so a zoom-while-panning
// motion still finishes together.
const SMOOTHING_MS = 220;

function easeOutCubic(t: number): number {
  return 1 - (1 - t) ** 3;
}

/**
 * Canvas 2D re-implementation of an older dx-drawn/HTML radar-map widget
 * (draggable + scroll-to-zoom, pins placed via world x/y) - rebuilt from
 * scratch against this project's actual stack instead of porting the
 * original's own event bus (`addEvent('maps', ...)`) and gamepad-axis
 * panning, neither of which exist here. Kept intentionally generic (pins +
 * an optional click handler, no spawn-specific logic) so SpawnSelectView.tsx
 * and a future F11 world-map/legend overlay can both build on the same
 * component instead of duplicating the canvas/drag/zoom math.
 */
export const Map2D: Component<Map2DProps> = (props) => {
  let canvas: HTMLCanvasElement | undefined;
  let containerRef: HTMLDivElement | undefined;
  const [mapImage, setMapImage] = createSignal<HTMLImageElement | null>(null);
  const [hoveredPin, setHoveredPin] = createSignal<MapPin | null>(null);
  const [hoverScreenPos, setHoverScreenPos] = createSignal({ x: 0, y: 0 });

  const initialZoom = props.initialZoom ?? props.minZoom ?? DEFAULT_MIN_ZOOM;

  // Drag/wheel input sets the *target* pan+zoom instantly; a
  // requestAnimationFrame loop below eases the *displayed* (rendered)
  // values toward that target every frame instead of snapping straight
  // to it - draw() only ever reads displayed*, never the target directly.
  let targetZoom = initialZoom;
  let targetCenterX = 0;
  let targetCenterY = 0;
  let displayedZoom = initialZoom;
  let displayedCenterX = 0;
  let displayedCenterY = 0;
  let animFrom = { zoom: initialZoom, x: 0, y: 0 };
  let animStart = 0;
  let animHandle = 0;

  let dragging = false;
  let lastClientX = 0;
  let lastClientY = 0;
  let dragMoved = false;

  const minZoom = () => props.minZoom ?? DEFAULT_MIN_ZOOM;
  const maxZoom = () => props.maxZoom ?? DEFAULT_MAX_ZOOM;
  const interactive = () => props.interactive ?? true;

  function startAnimating() {
    animFrom = { zoom: displayedZoom, x: displayedCenterX, y: displayedCenterY };
    animStart = performance.now();
    if (animHandle) return;

    const step = () => {
      const elapsed = performance.now() - animStart;
      const t = Math.min(elapsed / SMOOTHING_MS, 1);
      const eased = easeOutCubic(t);

      displayedZoom = animFrom.zoom + (targetZoom - animFrom.zoom) * eased;
      displayedCenterX = animFrom.x + (targetCenterX - animFrom.x) * eased;
      displayedCenterY = animFrom.y + (targetCenterY - animFrom.y) * eased;
      draw();

      if (t < 1) {
        animHandle = requestAnimationFrame(step);
      } else {
        animHandle = 0;
      }
    };
    animHandle = requestAnimationFrame(step);
  }

  onMount(() => {
    const image = new Image();
    image.src = mapTextureUrl;
    image.onload = () => setMapImage(image);
  });

  /** World (x/y) -> canvas-pixel space, given the canvas's own current size/zoom/center. Always reads the eased *displayed* values, never the raw target, so a mid-animation frame and a hit-test agree on what's actually on screen. */
  function worldToScreen(worldX: number, worldY: number, canvasWidth: number, canvasHeight: number) {
    const mapSize = Math.max(canvasWidth, canvasHeight) * displayedZoom;
    const originX = canvasWidth / 2 - (displayedCenterX / WORLD_SIZE) * mapSize;
    const originY = canvasHeight / 2 + (displayedCenterY / WORLD_SIZE) * mapSize;
    return {
      x: originX + (worldX / WORLD_SIZE) * mapSize,
      y: originY - (worldY / WORLD_SIZE) * mapSize,
    };
  }

  function draw() {
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dom = canvas.getBoundingClientRect();
    const width = dom.width;
    const height = dom.height;

    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }

    ctx.clearRect(0, 0, width, height);

    const image = mapImage();
    if (image) {
      const mapSize = Math.max(width, height) * displayedZoom;
      const origin = worldToScreen(0, 0, width, height);
      const imageLeft = origin.x - mapSize / 2;
      const imageTop = origin.y - mapSize / 2;
      ctx.drawImage(image, imageLeft, imageTop, mapSize, mapSize);
    }

    let selectedPinScreenPos: { x: number; y: number } | null = null;

    for (const pin of props.pins) {
      const pos = worldToScreen(pin.x, pin.y, width, height);
      const isHovered = interactive() && hoveredPin()?.id === pin.id;
      const radius = isHovered ? PIN_HOVER_RADIUS_PX : PIN_RADIUS_PX;

      ctx.beginPath();
      ctx.arc(pos.x, pos.y, radius, 0, Math.PI * 2);
      ctx.fillStyle = pin.color ?? "#3dd68c";
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = isHovered ? "#ffffff" : "rgba(0, 0, 0, 0.6)";
      ctx.stroke();

      if (props.selectedPinId != null && pin.id === props.selectedPinId) {
        selectedPinScreenPos = pos;
      }
    }

    if (props.onSelectedPinScreenPos) {
      // Reports null both when nothing is selected and when the selected
      // pin simply isn't in props.pins this frame - either way there's
      // nowhere sensible to anchor a panel, so the caller treats both the same.
      props.onSelectedPinScreenPos(props.selectedPinId != null ? selectedPinScreenPos : null);
    }
  }

  createEffect(() => {
    // Pan/zoom itself is driven by startAnimating()'s own rAF loop (plain
    // mutable variables, not signals - see the fields above), not by this
    // effect - it only needs to redraw on the other things that affect
    // the picture: hover state, the map image finishing its load, or the
    // pin list changing.
    hoveredPin();
    mapImage();
    props.pins;
    props.selectedPinId;
    draw();
  });

  createEffect(() => {
    const target = props.focusTarget;
    if (!target) return;

    targetCenterX = target.x;
    targetCenterY = target.y;
    if (target.zoom !== undefined) {
      targetZoom = Math.min(maxZoom(), Math.max(minZoom(), target.zoom));
    }
    startAnimating();
  });

  function findPinAt(clientX: number, clientY: number): MapPin | null {
    if (!canvas) return null;
    const dom = canvas.getBoundingClientRect();
    const x = clientX - dom.left;
    const y = clientY - dom.top;

    for (const pin of props.pins) {
      const pos = worldToScreen(pin.x, pin.y, dom.width, dom.height);
      const dx = pos.x - x;
      const dy = pos.y - y;
      if (Math.sqrt(dx * dx + dy * dy) <= PIN_HOVER_RADIUS_PX + 2) {
        return pin;
      }
    }
    return null;
  }

  function onPointerDown(event: PointerEvent) {
    if (event.button !== 0) return;
    dragging = true;
    dragMoved = false;
    lastClientX = event.clientX;
    lastClientY = event.clientY;
    canvas?.setPointerCapture(event.pointerId);
  }

  function onPointerMove(event: PointerEvent) {
    if (dragging) {
      const deltaX = event.clientX - lastClientX;
      const deltaY = event.clientY - lastClientY;
      if (Math.abs(deltaX) > 2 || Math.abs(deltaY) > 2) dragMoved = true;

      const dom = canvas?.getBoundingClientRect();
      if (dom) {
        const mapSize = Math.max(dom.width, dom.height) * displayedZoom;
        targetCenterX -= (deltaX / mapSize) * WORLD_SIZE;
        targetCenterY += (deltaY / mapSize) * WORLD_SIZE;
        // 1:1 with the cursor while actively dragging - no easing lag
        // fighting the mouse - only wheel-zoom (and drag release, since
        // displayed already equals target by then) gets the eased glide.
        displayedCenterX = targetCenterX;
        displayedCenterY = targetCenterY;
        draw();
      }

      lastClientX = event.clientX;
      lastClientY = event.clientY;
      return;
    }

    if (interactive()) {
      setHoveredPin(findPinAt(event.clientX, event.clientY));
      const dom = canvas?.getBoundingClientRect();
      if (dom) setHoverScreenPos({ x: event.clientX - dom.left, y: event.clientY - dom.top });
    }
  }

  function onPointerUp(event: PointerEvent) {
    dragging = false;
    canvas?.releasePointerCapture(event.pointerId);

    if (!dragMoved && interactive()) {
      const pin = findPinAt(event.clientX, event.clientY);
      if (pin) props.onPinClick?.(pin);
    }
  }

  function onPointerLeave() {
    setHoveredPin(null);
  }

  function onWheel(event: WheelEvent) {
    event.preventDefault();
    const delta = -event.deltaY * ZOOM_WHEEL_SENSITIVITY;
    targetZoom = Math.min(maxZoom(), Math.max(minZoom(), targetZoom + delta));
    startAnimating();
  }

  let resizeObserver: ResizeObserver | undefined;
  onMount(() => {
    if (containerRef) {
      resizeObserver = new ResizeObserver(() => draw());
      resizeObserver.observe(containerRef);
    }
  });
  onCleanup(() => {
    resizeObserver?.disconnect();
    if (animHandle) cancelAnimationFrame(animHandle);
  });

  return (
    <div ref={containerRef} class={cn(styles.root, props.class)}>
      <canvas
        ref={canvas}
        class={styles.canvas}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerLeave={onPointerLeave}
        onWheel={onWheel}
      />

      <Show when={interactive() && hoveredPin()}>
        {(pin) => (
          <div
            class={styles.pinTooltip}
            style={{ left: `${hoverScreenPos().x}px`, top: `${hoverScreenPos().y - PIN_HOVER_RADIUS_PX - 10}px` }}
          >
            <span class={styles.pinTooltipTitle}>{pin().label}</span>
            <Show when={pin().description}>
              <span class={styles.pinTooltipDescription}>{pin().description}</span>
            </Show>
          </div>
        )}
      </Show>
    </div>
  );
};
