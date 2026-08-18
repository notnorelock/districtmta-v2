// `window.mta` only exists inside MTA's CEF runtime, never in a plain browser tab -
// a reliable signal for which transport to use.
declare global {
  interface Window {
    mta?: {
      triggerEvent: (eventName: string, ...args: unknown[]) => void;
    };
  }
}

export function isMtaEnvironment(): boolean {
  return typeof window !== "undefined" && typeof window.mta?.triggerEvent === "function";
}
