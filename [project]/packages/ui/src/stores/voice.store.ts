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

// Solid's <For> (mapArray under the hood) keys rows by object IDENTITY,
// not by value - Lua pushes a brand-new { name, mode } table every single
// time ANYONE's talking state changes, so without this cache every push
// would hand <For> all-new object references for speakers who didn't
// actually change, which reads as "that row left, a new one arrived" to
// TransitionGroup and showed as a flickering duplicate instead of one
// stable row. Keyed by name (not identity) and mutated in place when a
// speaker's mode changes, so the same speaker keeps the same object
// reference across pushes and <For> correctly sees "this row is still here".
const speakerObjectsByName = new Map<string, NearbySpeaker>();

mta.on("voice.nearbyUpdated", (data) => {
  const incoming = (data as VoiceNearbyUpdatedPayload).speakers;
  const incomingNames = new Set(incoming.map((speaker) => speaker.name));

  for (const name of speakerObjectsByName.keys()) {
    if (!incomingNames.has(name)) {
      speakerObjectsByName.delete(name);
    }
  }

  const resolved = incoming.map((speaker) => {
    const existing = speakerObjectsByName.get(speaker.name);
    if (existing) {
      existing.mode = speaker.mode;
      return existing;
    }
    speakerObjectsByName.set(speaker.name, speaker);
    return speaker;
  });

  setNearbySpeakers(resolved);
});
