import type { MtaFetchRequestEnvelope, MtaPushEventName, MtaResponse } from "@/types/api";
import type { RememberedAccount } from "@/types/account";
import type { MtaTransportLike } from "./Transport";
import { obfuscatePayload, deobfuscatePayload } from "./payloadObfuscation";

const ACCOUNTS_LIST_TIMEOUT_MS = 3000;
const TRUSTED_DEVICE_LOAD_TIMEOUT_MS = 3000;

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

  upsertAccount(login: string, password: string, rememberPassword: boolean): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot upsertAccount");
      return;
    }

    const payload = { login, password, rememberPassword };
    const obfuscated = obfuscatePayload(JSON.stringify(payload), this.sessionKey());
    window.mta.triggerEvent("accounts.upsert", obfuscated);
  }

  touchAccount(login: string): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot touchAccount");
      return;
    }

    const obfuscated = obfuscatePayload(JSON.stringify({ login }), this.sessionKey());
    window.mta.triggerEvent("accounts.touch", obfuscated);
  }

  removeAccount(login: string): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot removeAccount");
      return;
    }

    const obfuscated = obfuscatePayload(JSON.stringify({ login }), this.sessionKey());
    window.mta.triggerEvent("accounts.remove", obfuscated);
  }

  listAccounts(): Promise<RememberedAccount[]> {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot listAccounts");
      return Promise.resolve([]);
    }

    return new Promise((resolve) => {
      let settled = false;

      const timeoutId = window.setTimeout(() => {
        if (settled) return;
        settled = true;
        delete window.__mtaAccountsLoaded;
        console.warn("[MtaTransport] listAccounts timed out");
        resolve([]);
      }, ACCOUNTS_LIST_TIMEOUT_MS);

      window.__mtaAccountsLoaded = (obfuscatedResponse: string) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timeoutId);
        delete window.__mtaAccountsLoaded;

        const parsed = this.parseObfuscated<{ accounts: RememberedAccount[] | null }>(obfuscatedResponse);
        if (!parsed.ok || !Array.isArray(parsed.value.accounts)) {
          resolve([]);
          return;
        }

        resolve(parsed.value.accounts);
      };

      window.mta!.triggerEvent("accounts.list");
    });
  }

  saveTrustedDeviceToken(login: string, token: string): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot saveTrustedDeviceToken");
      return;
    }

    const obfuscated = obfuscatePayload(JSON.stringify({ login, token }), this.sessionKey());
    window.mta.triggerEvent("trustedDevice.save", obfuscated);
  }

  clearTrustedDeviceToken(login: string): void {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot clearTrustedDeviceToken");
      return;
    }

    const obfuscated = obfuscatePayload(JSON.stringify({ login }), this.sessionKey());
    window.mta.triggerEvent("trustedDevice.clear", obfuscated);
  }

  loadTrustedDeviceToken(login: string): Promise<string | null> {
    if (typeof window.mta?.triggerEvent !== "function") {
      console.error("[MtaTransport] window.mta.triggerEvent is not available - cannot loadTrustedDeviceToken");
      return Promise.resolve(null);
    }

    return new Promise((resolve) => {
      let settled = false;

      const timeoutId = window.setTimeout(() => {
        if (settled) return;
        settled = true;
        delete window.__mtaTrustedDeviceLoaded;
        console.warn("[MtaTransport] loadTrustedDeviceToken timed out");
        resolve(null);
      }, TRUSTED_DEVICE_LOAD_TIMEOUT_MS);

      window.__mtaTrustedDeviceLoaded = (obfuscatedResponse: string) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timeoutId);
        delete window.__mtaTrustedDeviceLoaded;

        const parsed = this.parseObfuscated<{ token: string | null }>(obfuscatedResponse);
        if (!parsed.ok || !parsed.value.token) {
          resolve(null);
          return;
        }

        resolve(parsed.value.token);
      };

      const obfuscated = obfuscatePayload(JSON.stringify({ login }), this.sessionKey());
      window.mta!.triggerEvent("trustedDevice.load", obfuscated);
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
    __mtaAccountsLoaded?: (obfuscatedResponse: string) => void;
    __mtaTrustedDeviceLoaded?: (obfuscatedResponse: string) => void;
    __mtaSessionKey?: string;
  }
}
