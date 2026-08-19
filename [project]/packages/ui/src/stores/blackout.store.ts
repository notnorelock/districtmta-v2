import { createSignal } from "solid-js";
import { mta } from "@/lib/mta/MtaBridge";

/**
 * Mirrors the payload shape gm_blackout/client/BlackoutState.lua pushes
 * over "blackout.updated" - always a { secondsRemaining, totalDuration,
 * canSelfRevive } object. Lua's own `nil` can't cross
 * exports.core_ui:uiPushEvent (a nil argument is dropped, not passed
 * through) and a table field set to nil never creates the key at all, so
 * the Lua side normalizes "not blacked out" to `secondsRemaining = false`/
 * `totalDuration = false` - false is what arrives here, not null/undefined.
 */
interface BlackoutUpdatedPayload {
  secondsRemaining: number | false;
  totalDuration: number | false;
  canSelfRevive: boolean;
}

const [secondsRemaining, setSecondsRemaining] = createSignal<number | null>(null);
/** Total seconds the current blackout was started with - server-authoritative, used to normalize the CEF ring's progress (BlackoutService's durationSeconds argument can differ per call, never assume a fixed constant). */
const [totalDuration, setTotalDuration] = createSignal<number | null>(null);
/** True once the countdown has run out and pressing E actually ends blackout - see BlackoutState.lua. */
const [canSelfRevive, setCanSelfRevive] = createSignal(false);

export const blackoutStore = {
  secondsRemaining,
  totalDuration,
  canSelfRevive,
};

mta.on("blackout.updated", (data) => {
  const payload = data as BlackoutUpdatedPayload;
  setSecondsRemaining(payload.secondsRemaining === false ? null : payload.secondsRemaining);
  setTotalDuration(payload.totalDuration === false ? null : payload.totalDuration);
  setCanSelfRevive(payload.canSelfRevive);
});
