import type { Component } from "solid-js";
import logoUrl from "@/assets/brand/logo_v1.png";
import wordmarkUrl from "@/assets/brand/wordmark.png";

export interface LogoProps {
  /** Tailwind height utility for the square mark (e.g. "h-6") - the
   *  wordmark is sized relative to this via markHeightClass below, not
   *  passed separately, so callers only ever tune one knob. */
  markHeightClass?: string;
  /** Tailwind height utility for the wordmark image - defaults smaller
   *  than the mark (wordmark.png's own glyphs read as "too thin/small"
   *  next to the mark at equal heights - see ScoreboardOverlay/DashboardView's
   *  own former h-6/h-4 split this was extracted from). */
  wordmarkHeightClass?: string;
  class?: string;
}

/**
 * Brand lockup: the square mark (assets/brand/logo_v1.png) and the
 * "districtMTA" wordmark (assets/brand/wordmark.png) side by side - two
 * SEPARATE image assets, not one combined file, because the wordmark
 * image alone reads too small/thin without the mark next to it. Shared
 * here (ScoreboardOverlay.tsx, DashboardView.tsx) instead of each header
 * duplicating its own <img> pair + import lines.
 */
export const Logo: Component<LogoProps> = (props) => {
  return (
    <div class={`flex shrink-0 items-center gap-2 ${props.class ?? ""}`}>
      <img src={logoUrl} alt="" class={`w-auto ${props.markHeightClass ?? "h-6"}`} />
      <img src={wordmarkUrl} alt="districtMTA" class={`w-auto ${props.wordmarkHeightClass ?? "h-4"}`} />
    </div>
  );
};
