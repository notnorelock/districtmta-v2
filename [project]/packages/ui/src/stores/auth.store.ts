import { createSignal } from "solid-js";
import type { Account } from "@/types/account";
import type { ApiErrorCode } from "@/types/api";
import { authApi } from "@/lib/api/authApi";
import { mta } from "@/lib/mta/MtaBridge";

export type AuthPhase = "checking" | "unauthenticated" | "authenticated" | "error";

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
    setPhase("authenticated");
    return true;
  },

  async login(login: string, password: string): Promise<boolean> {
    setLastError(null);
    const response = await authApi.login({ login, password });

    if (!response.success) {
      setLastError(response.error.code);
      return false;
    }

    setAccount(response.data);
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
