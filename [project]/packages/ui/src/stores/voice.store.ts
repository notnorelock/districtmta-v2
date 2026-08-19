import { createSignal } from "solid-js";
import type { NearbySpeaker } from "@/types/voice";
import { mta } from "@/lib/mta/MtaBridge";

/** Mirrors the payload shape gm_voice/client/VoiceState.lua pushes over "voice.nearbyUpdated". */
interface VoiceNearbyUpdatedPayload {
  speakers: NearbySpeaker[];
}

const [nearbySpeakers, setNearbySpeakers] = createSignal<readonly NearbySpeaker[]>([]);

export const voiceStore = {
  nearbySpeakers,
};

mta.on("voice.nearbyUpdated", (data) => {
  setNearbySpeakers((data as VoiceNearbyUpdatedPayload).speakers);
});
