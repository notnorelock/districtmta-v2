import { mta } from "@/lib/mta/MtaBridge";
import type { MtaResponse } from "@/types/api";
import type { Account, AuthStatus, LoginAccountInput, RegisterAccountInput } from "@/types/account";

// Typed wrapper over the auth.* FetchBridge endpoints - keeps raw endpoint strings here.
export const authApi = {
  status(): Promise<MtaResponse<AuthStatus>> {
    return mta.fetch<AuthStatus>("auth.status", []);
  },

  register(input: RegisterAccountInput): Promise<MtaResponse<Account>> {
    return mta.fetch<Account>("auth.register", [input]);
  },

  login(input: LoginAccountInput): Promise<MtaResponse<Account>> {
    return mta.fetch<Account>("auth.login", [input]);
  },
};
