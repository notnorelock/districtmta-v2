/** Mirrors the payload shape gm_blackout/client/BlackoutState.lua pushes over "blackout.updated". */
export interface BlackoutState {
  /** Seconds left until blackout ends, or null when not currently blacked out. */
  secondsRemaining: number | null;
}
