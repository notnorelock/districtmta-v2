/** Mirrors the payload shape ui_hud/client/HudState.lua pushes over "hud.updated". */
export interface HudStats {
  /** 0-100, real (getElementHealth) */
  health: number;
  /** 0-100, placeholder - no server-side hunger system yet */
  hunger: number;
  /** 0-100, placeholder - no server-side thirst system yet */
  thirst: number;
  /** placeholder - no real voice-chat activity signal wired up yet */
  voiceActive: boolean;
}
