import type { MtaFetchRequestEnvelope, MtaResponse } from "@/types/api";
import type { Account, RememberedAccount } from "@/types/account";
import { AccountRole } from "@/types/account";
import type { MtaTransportLike } from "./Transport";

const DEV_LATENCY_MS = 350;
// Not obfuscated: this is a dev-only stand-in and never ships.
const DEV_ACCOUNTS_STORAGE_KEY = "district.dev.rememberedAccounts";
const DEV_TRUSTED_DEVICE_STORAGE_KEY_PREFIX = "district.dev.trustedDeviceToken";
const MAX_ACCOUNTS = 5;

// Several fake accounts can exist in dev mode now that the login screen
// is a multi-account switcher - register() pushes a new entry, login()
// searches the array, matching CredentialStore.lua's own multi-account
// shape so the switcher UI can actually be developed/tested against it.
const mockAccounts: Array<{ account: Account; password: string }> = [];
let nextMockId = 1;
// Tracks which mock account (if any) the current dev-mode page session
// is "logged in" as - unlike mockAccounts (a list, multiple can exist so
// the switcher UI has something to develop against), only one can be the
// active session at a time, mirroring the real server's own single-
// session-per-connection model.
let currentMockAccount: Account | null = null;

function readRememberedAccounts(): RememberedAccount[] {
  const raw = window.localStorage.getItem(DEV_ACCOUNTS_STORAGE_KEY);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as RememberedAccount[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeRememberedAccounts(accounts: RememberedAccount[]): void {
  window.localStorage.setItem(DEV_ACCOUNTS_STORAGE_KEY, JSON.stringify(accounts));
}

function findIndexByLogin(accounts: RememberedAccount[], login: string): number {
  const needle = login.toLowerCase();
  return accounts.findIndex((account) => account.login.toLowerCase() === needle);
}

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

  upsertAccount(login: string, password: string, rememberPassword: boolean): void {
    const accounts = readRememberedAccounts();
    const now = Date.now() / 1000;
    const storedPassword = rememberPassword ? password : undefined;

    const existingIndex = findIndexByLogin(accounts, login);
    if (existingIndex >= 0) {
      const existing = accounts[existingIndex]!;
      accounts[existingIndex] = { ...existing, password: storedPassword, lastUsedAt: now };
    } else {
      accounts.push({ login, password: storedPassword, savedAt: now, lastUsedAt: now });
    }

    if (accounts.length > MAX_ACCOUNTS) {
      let oldestIndex = 0;
      for (let i = 1; i < accounts.length; i++) {
        if (accounts[i]!.lastUsedAt < accounts[oldestIndex]!.lastUsedAt) oldestIndex = i;
      }
      accounts.splice(oldestIndex, 1);
    }

    writeRememberedAccounts(accounts);
  }

  touchAccount(login: string): void {
    const accounts = readRememberedAccounts();
    const index = findIndexByLogin(accounts, login);
    if (index < 0) return;

    const existing = accounts[index]!;
    accounts[index] = { ...existing, lastUsedAt: Date.now() / 1000 };
    writeRememberedAccounts(accounts);
  }

  removeAccount(login: string): void {
    const accounts = readRememberedAccounts();
    const index = findIndexByLogin(accounts, login);
    if (index < 0) return;

    accounts.splice(index, 1);
    writeRememberedAccounts(accounts);
  }

  listAccounts(): Promise<RememberedAccount[]> {
    return new Promise((resolve) => {
      window.setTimeout(() => {
        const accounts = [...readRememberedAccounts()].sort((a, b) => b.lastUsedAt - a.lastUsedAt);
        resolve(accounts);
      }, DEV_LATENCY_MS);
    });
  }

  saveTrustedDeviceToken(login: string, token: string): void {
    window.localStorage.setItem(`${DEV_TRUSTED_DEVICE_STORAGE_KEY_PREFIX}:${login.toLowerCase()}`, token);
  }

  clearTrustedDeviceToken(login: string): void {
    window.localStorage.removeItem(`${DEV_TRUSTED_DEVICE_STORAGE_KEY_PREFIX}:${login.toLowerCase()}`);
  }

  loadTrustedDeviceToken(login: string): Promise<string | null> {
    return new Promise((resolve) => {
      window.setTimeout(() => {
        resolve(window.localStorage.getItem(`${DEV_TRUSTED_DEVICE_STORAGE_KEY_PREFIX}:${login.toLowerCase()}`));
      }, DEV_LATENCY_MS);
    });
  }

  private resolve(envelope: MtaFetchRequestEnvelope): void {
    const payload = envelope.arguments[0] as Record<string, unknown> | undefined;
    const respond = (response: MtaResponse<unknown>) => this.responseHandler?.(envelope.id, response);

    switch (envelope.endpoint) {
      case "auth.status": {
        respond({ success: true, data: { authenticated: currentMockAccount !== null, account: currentMockAccount } });
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

        const account: Account = { id: nextMockId++, login, email, isPremium: false, premiumExpiresAt: null, role: AccountRole.PLAYER, twoFactorEnabled: false };
        mockAccounts.push({ account, password });
        currentMockAccount = account;

        respond({ success: true, data: account });
        return;
      }

      case "auth.login": {
        const login = typeof payload?.login === "string" ? payload.login : "";
        const password = typeof payload?.password === "string" ? payload.password : "";

        const match = mockAccounts.find((entry) => (login === entry.account.login || login === entry.account.email) && password === entry.password);
        if (!match) {
          respond({ success: false, error: { code: "INVALID_CREDENTIALS" } });
          return;
        }

        currentMockAccount = match.account;
        respond({ success: true, data: match.account });
        return;
      }

      case "account.current": {
        if (!currentMockAccount) {
          respond({ success: false, error: { code: "NOT_AUTHENTICATED" } });
          return;
        }
        respond({ success: true, data: currentMockAccount });
        return;
      }

      default: {
        respond({ success: false, error: { code: "UNKNOWN_ENDPOINT" } });
      }
    }
  }
}
