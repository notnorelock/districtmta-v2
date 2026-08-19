/** Mirrors Enums.VoiceMode in core_shared/shared/Enums.lua - keep in sync. */
export type VoiceMode = "whisper" | "talk" | "shout";

/** One entry of the list gm_voice/client/VoiceState.lua pushes over "voice.nearbyUpdated". */
export interface NearbySpeaker {
  name: string;
  mode: VoiceMode;
}
