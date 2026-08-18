import type { MtaFetchRequestEnvelope, MtaResponse } from "@/types/api";
import type { Account, SavedCredentials } from "@/types/account";
import { AccountRole } from "@/types/account";
import type { MtaTransportLike } from "./Transport";

const DEV_LATENCY_MS = 350;
// Not obfuscated: this is a dev-only stand-in and never ships.
const DEV_CREDENTIALS_STORAGE_KEY = "district.dev.savedCredentials";

let mockAccount: Account | null = null;
let mockPassword: string | null = null;
let nextMockId = 1;

/** Fakes FetchBridge for `pnpm dev` outside MTA's CEF. Only covers the auth slice. */
export class BrowserDevTransport implements MtaTransportLike {
  private responseHandler: ((requestId: string, response: MtaResponse<unknown>) => void) | null = null;

  send(envelope: MtaFetchRequestEnvelope): void {
    window.setTimeout(() => this.resolve(envelope), DEV_LATENCY_MS);
  }

  onResponse(handler: (requestId: string, response: MtaResponse<unknown>) => void): () => void {
    this.responseHandler = handler;
    return () => {
      this.responseHandler = null;
    };
  }

  onPush(): () => void {
    return () => {};
  }

  notify(): void {}

  saveCredentials(login: string, password: string): void {
    const payload: SavedCredentials = { login, password };
    window.localStorage.setItem(DEV_CREDENTIALS_STORAGE_KEY, JSON.stringify(payload));
  }

  clearCredentials(): void {
    window.localStorage.removeItem(DEV_CREDENTIALS_STORAGE_KEY);
  }

  loadCredentials(): Promise<SavedCredentials | null> {
    return new Promise((resolve) => {
      window.setTimeout(() => {
        const raw = window.localStorage.getItem(DEV_CREDENTIALS_STORAGE_KEY);
        if (!raw) {
          resolve(null);
          return;
        }
        try {
          resolve(JSON.parse(raw) as SavedCredentials);
        } catch {
          resolve(null);
        }
      }, DEV_LATENCY_MS);
    });
  }

  private resolve(envelope: MtaFetchRequestEnvelope): void {
    const payload = envelope.arguments[0] as Record<string, unknown> | undefined;
    const respond = (response: MtaResponse<unknown>) => this.responseHandler?.(envelope.id, response);

    switch (envelope.endpoint) {
      case "auth.status": {
        respond({ success: true, data: { authenticated: mockAccount !== null, account: mockAccount } });
        return;
      }

      case "auth.register": {
        const login = typeof payload?.login === "string" ? payload.login : "";
        const email = typeof payload?.email === "string" ? payload.email : "";
        const password = typeof payload?.password === "string" ? payload.password : "";

        if (login.length < 3) {
          respond({ success: false, error: { code: "INVALID_LOGIN" } });
          return;
        }

        if (!email.includes("@")) {
          respond({ success: false, error: { code: "INVALID_EMAIL" } });
          return;
        }

        if (password.length < 8) {
          respond({ success: false, error: { code: "INVALID_PASSWORD" } });
          return;
        }

        mockAccount = { id: nextMockId++, login, email, isPremium: false, premiumExpiresAt: null, role: AccountRole.PLAYER };
        mockPassword = password;

        respond({ success: true, data: mockAccount });
        return;
      }

      case "auth.login": {
        const login = typeof payload?.login === "string" ? payload.login : "";
        const password = typeof payload?.password === "string" ? payload.password : "";

        if (!mockAccount || (login !== mockAccount.login && login !== mockAccount.email) || password !== mockPassword) {
          respond({ success: false, error: { code: "INVALID_CREDENTIALS" } });
          return;
        }

        respond({ success: true, data: mockAccount });
        return;
      }

      case "account.current": {
        if (!mockAccount) {
          respond({ success: false, error: { code: "NOT_AUTHENTICATED" } });
          return;
        }
        respond({ success: true, data: mockAccount });
        return;
      }

      default: {
        respond({ success: false, error: { code: "UNKNOWN_ENDPOINT" } });
      }
    }
  }
}
