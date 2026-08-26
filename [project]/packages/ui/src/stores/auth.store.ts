import { createSignal } from "solid-js";
import type { Account } from "@/types/account";
import type { ApiErrorCode } from "@/types/api";
import { authApi } from "@/lib/api/authApi";
import { mta } from "@/lib/mta/MtaBridge";

export type AuthPhase = "checking" | "unauthenticated" | "securingAccount" | "authenticated" | "error";

export type LoginResult = "success" | "twoFactorRequired" | "error";

const [phase, setPhase] = createSignal<AuthPhase>("checking");
const [account, setAccount] = createSignal<Account | null>(null);
const [lastError, setLastError] = createSignal<ApiErrorCode | null>(null);

export const authStore = {
  phase,
  account,
  lastError,

  async checkStatus(): Promise<void> {
    setPhase("checking");
    const response = await authApi.status();
    console.log("[authStore] auth.status response", response);

    if (!response.success) {
      setLastError(response.error.code);
      setPhase("error");
      return;
    }

    if (response.data.authenticated && response.data.account) {
      setAccount(response.data.account);
      setPhase("authenticated");
    } else {
      setPhase("unauthenticated");
    }
  },

  async register(login: string, email: string, password: string): Promise<boolean> {
    setLastError(null);
    const response = await authApi.register({ login, email, password });

    if (!response.success) {
      setLastError(response.error.code);
      return false;
    }

    setAccount(response.data);
    setPhase("securingAccount");
    return true;
  },

  /**
   * The only path from "securingAccount" to "authenticated" - called once
   * the post-registration 2FA step resolves, whether the player actually
   * configured 2FA (account.confirmTwoFactorSetup already succeeded by
   * then) or explicitly skipped it. Doesn't call any account.* endpoint
   * itself - purely finishes the CEF-local phase transition.
   */
  finishSecuringAccount(): void {
    setPhase("authenticated");
  },

  async login(login: string, password: string): Promise<LoginResult> {
    setLastError(null);
    const trustToken = await mta.loadTrustedDeviceToken();
    const response = await authApi.login({ login, password, trustToken: trustToken ?? undefined });

    if (!response.success) {
      setLastError(response.error.code);
      if (response.error.code === "TWO_FACTOR_REQUIRED") {
        return "twoFactorRequired";
      }
      return "error";
    }

    setAccount(response.data);
    setPhase("authenticated");
    return "success";
  },

  async verifyTwoFactor(code: string, trustDevice: boolean): Promise<boolean> {
    setLastError(null);
    const response = await authApi.verifyTwoFactor({ code, trustDevice });

    if (!response.success) {
      setLastError(response.error.code);
      return false;
    }

    if (response.data.trustToken) {
      mta.saveTrustedDeviceToken(response.data.trustToken);
    }

    setAccount(response.data.account);
    setPhase("authenticated");
    return true;
  },
};

mta.on("account.resolved", (data) => {
  setAccount(data as Account);
  setPhase("authenticated");
});

mta.on("account.updated", (data) => {
  setAccount(data as Account);
});
