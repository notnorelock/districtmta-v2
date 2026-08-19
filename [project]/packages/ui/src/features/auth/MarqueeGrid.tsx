import { type Component, For } from "solid-js";
import styles from "./MarqueeGrid.module.scss";
import logoUrl from "@/assets/textures/logo.png";

// Right-side auth panel backdrop - a grid of tiles in columns, each
// column scrolling independently (alternating up/down, staggered
// speeds) and the whole grid rotated on a diagonal, oversized so the
// rotation never exposes an empty edge regardless of panel size. Pure
// CSS animation (translateY keyframes, content duplicated per column so
// the loop point is invisible) - no per-frame JS, cheap inside CEF.
// Tiles have no background of their own - just the project logo,
// faded - see MarqueeGrid.module.scss.

const COLUMN_COUNT = 10;
// MUST match $tiles-per-column in MarqueeGrid.module.scss - that value
// drives $copy-height (the exact px distance each loop iteration
// scrolls), so the two have to describe the same list length or the
// loop restart point drifts from where the DOM copy boundary actually
// is, which is what caused the visible jump/stutler at the end of the
// original -50%-based version.
const TILES_PER_COLUMN = 10;
// Every column repeats its own tile list twice back-to-back and animates
// exactly one repeat's height of translateY - that's what makes the loop
// seamless (the moment the first copy scrolls fully offscreen, the
// second copy is sitting exactly where the first one started).
const REPEAT_COUNT = 2;

const COLUMN_DURATIONS_S = [22, 26, 19, 24, 21, 27, 23, 25, 20, 28];

export const MarqueeGrid: Component = () => {
  const columns = Array.from({ length: COLUMN_COUNT }, (_, columnIndex) => ({
    id: columnIndex,
    reverse: columnIndex % 2 === 1,
    durationS: COLUMN_DURATIONS_S[columnIndex % COLUMN_DURATIONS_S.length],
    tiles: Array.from({ length: TILES_PER_COLUMN * REPEAT_COUNT }, (_, tileIndex) => tileIndex),
  }));

  return (
    <div class={styles.viewport}>
      <div class={styles.grid}>
        <For each={columns}>
          {(column) => (
            <div
              class={column.reverse ? `${styles.column} ${styles.columnReverse}` : styles.column}
              style={{ "animation-duration": `${column.durationS}s` }}
            >
              <For each={column.tiles}>
                {() => (
                  <div class={styles.tile}>
                    <img src={logoUrl} alt="" class={styles.tileLogo} />
                  </div>
                )}
              </For>
            </div>
          )}
        </For>
      </div>
    </div>
  );
};
