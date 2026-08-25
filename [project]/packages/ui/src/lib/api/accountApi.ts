import { mta } from "@/lib/mta/MtaBridge";
import type { MtaResponse } from "@/types/api";
import type { ChangePasswordInput } from "@/types/account";

// Typed wrapper over the account.* FetchBridge endpoints - keeps raw endpoint strings here.
export const accountApi = {
  changePassword(input: ChangePasswordInput): Promise<MtaResponse<{ ok: boolean }>> {
    return mta.fetch<{ ok: boolean }>("account.changePassword", [input]);
  },
};
