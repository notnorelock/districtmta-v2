import type { MtaFetchRequestEnvelope, MtaPushEventName, MtaResponse } from "@/types/api";
import type { SavedCredentials } from "@/types/account";
import type { MtaTransportLike } from "./Transport";
import { obfuscatePayload, deobfuscatePayload } from "./payloadObfuscation";

const CREDENTIALS_LOAD_TIMEOUT_MS = 3000;

/** Real transport used inside MTA's CEF browser. See docs/UiBridge.md for the protocol. */
export class MtaTransport implements MtaTransportLike {
  private sessionKey(): string | undefined {
    return window.__mtaSessionKey;
  }

  send(envelope: MtaFetchRequestEnvelope): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot send", envelope);
      return;
    }

    const obfuscated = obfuscatePayload(JSON.stringify(envelope), this.sessionKey());
    console.log("[MtaTransport] window.mta.triggerEvent('ui:fetchData', ...)", envelope);
    window.mta.triggerEvent("ui:fetchData", obfuscated);
  }

  onResponse(handler: (requestId: string, response: MtaResponse<unknown>) => void): () => void {
    window.__mtaFetchResponse = (requestId: string, obfuscatedResponse: string) => {
      const parsed = this.parseObfuscated<MtaResponse<unknown>>(obfuscatedResponse);
      if (!parsed.ok) {
        console.error("[MtaTransport] failed to deobfuscate/parse fetch response", requestId);
        return;
      }
      console.log("[MtaTransport] window.__mtaFetchResponse called by Lua", requestId, parsed.value);
      handler(requestId, parsed.value);
    };

    console.log("[MtaTransport] window.__mtaFetchResponse installed", typeof window.__mtaFetchResponse);

    return () => {
      delete window.__mtaFetchResponse;
    };
  }

  onPush(handler: (event: MtaPushEventName | string, data: unknown) => void): () => void {
    window.__mtaPushEvent = (event: string, obfuscatedData: string) => {
      const parsed = this.parseObfuscated<unknown>(obfuscatedData);
      if (!parsed.ok) {
        console.error("[MtaTransport] failed to deobfuscate/parse push event", event);
        return;
      }
      console.log("[MtaTransport] window.__mtaPushEvent called by Lua", event, parsed.value);
      handler(event, parsed.value);
    };

    console.log("[MtaTransport] window.__mtaPushEvent installed", typeof window.__mtaPushEvent);

    return () => {
      delete window.__mtaPushEvent;
    };
  }

  notify(eventName: string, ...args: unknown[]): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot notify", eventName, args);
      return;
    }

    // Routed through the single "ui.notify" channel (see Events.lua's own
    // UI_NOTIFY comment) instead of window.mta.triggerEvent(eventName, ...args)
    // directly - that crossing stringifies every argument regardless of
    // its real JS type (confirmed live: a JS number arrived as a Lua
    // STRING), which silently broke every consumer expecting a real
    // number/table. core_ui/client/ui/Transport.lua's UI_NOTIFY handler
    // JSON-decodes argsJson and re-fires the real eventName with real
    // typed args for whichever resource actually owns it.
    //
    // Wrapped as { args } rather than JSON.stringify(args) directly -
    // MTA's own fromJSON (confirmed live) auto-UNWRAPS a top-level
    // single-element JSON array back down to the bare value instead of a
    // one-element table (e.g. fromJSON("[1]") returns the number 1, not
    // {1}), which is also why toJsonValue() in Utils.lua strips the outer
    // brackets toJSON always adds - it's compensating for the same
    // behavior in the other direction. Wrapping in an object with a named
    // "args" key sidesteps that unwrap entirely, so the receiving side
    // always gets a real table back, whether args has 0, 1, or N entries.
    console.log("[MtaTransport] window.mta.triggerEvent (notify)", eventName, args);
    window.mta.triggerEvent("ui.notify", eventName, JSON.stringify({ args }));
  }

  saveCredentials(login: string, password: string): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot saveCredentials");
      return;
    }

    const payload: SavedCredentials = { login, password };
    const obfuscated = obfuscatePayload(JSON.stringify(payload), this.sessionKey());
    window.mta.triggerEvent("credentials.save", obfuscated);
  }

  clearCredentials(): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot clearCredentials");
      return;
    }

    window.mta.triggerEvent("credentials.clear");
  }

  loadCredentials(): Promise<SavedCredentials | null> {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot loadCredentials");
      return Promise.resolve(null);
    }

    return new Promise((resolve) => {
      let settled = false;

      const timeoutId = window.setTimeout(() => {
        if (settled) return;
        settled = true;
        delete window.__mtaCredentialsLoaded;
        console.warn("[MtaTransport] loadCredentials timed out");
        resolve(null);
      }, CREDENTIALS_LOAD_TIMEOUT_MS);

      window.__mtaCredentialsLoaded = (obfuscatedResponse: string) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timeoutId);
        delete window.__mtaCredentialsLoaded;

        const parsed = this.parseObfuscated<{ login: string | null; password: string | null }>(obfuscatedResponse);
        if (!parsed.ok || !parsed.value.login || !parsed.value.password) {
          resolve(null);
          return;
        }

        resolve({ login: parsed.value.login, password: parsed.value.password });
      };

      window.mta!.triggerEvent("credentials.load");
    });
  }

  // Session key may not have arrived yet when a response does; fall back to plaintext JSON.
  private parseObfuscated<T>(raw: string): { ok: true; value: T } | { ok: false } {
    const key = this.sessionKey();

    try {
      return { ok: true, value: JSON.parse(deobfuscatePayload(raw, key)) as T };
    } catch {
      // fall through to the plaintext attempt below
    }

    try {
      return { ok: true, value: JSON.parse(raw) as T };
    } catch (error) {
      console.error("[MtaTransport] deobfuscate/parse failed", error);
      return { ok: false };
    }
  }
}

declare global {
  interface Window {
    __mtaFetchResponse?: (requestId: string, obfuscatedResponse: string) => void;
    __mtaPushEvent?: (event: string, obfuscatedData: string) => void;
    __mtaCredentialsLoaded?: (obfuscatedResponse: string) => void;
    __mtaSessionKey?: string;
  }
}
