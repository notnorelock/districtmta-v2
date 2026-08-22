/** Native radar's own screen-space box (real px, dxDraw - see RadarComponent.lua's own getPosition()), CEF renders 1:1 so these are usable directly as px. */
export interface RadarPosition {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** Mirrors the payload shape ui_hud/client/HudState.lua pushes over "hud.updated". */
export interface HudStats {
  /** 0-100, real (getElementHealth) */
  health: number;
  /** 0-100, placeholder - no server-side hunger system yet */
  hunger: number;
  /** 0-100, placeholder - no server-side thirst system yet */
  thirst: number;
  /** 0-100, real (getPedOxygenLevel) - only meaningful while `drowning` is true */
  oxygen: number;
  /** True once oxygen is depleting (underwater) - drives whether the lungs icon renders at all */
  drowning: boolean;
  /** True while the local player is transmitting on gm_voice */
  voiceActive: boolean;
  /** 0-100, only meaningful while voiceActive - 33/66/100 for whisper/talk/shout (gm_voice's Enums.VoiceMode) */
  voiceLevel: number;
  /** ui_hud's native RadarComponent visibility - lets other CEF elements (VoiceIndicator) dock beside it */
  radarVisible: boolean;
  /** false whenever the native RadarComponent isn't ready yet - same "false means not ready" convention Bootstrap.lua's own getRadarPosition() uses */
  radarPosition: RadarPosition | false;
}
