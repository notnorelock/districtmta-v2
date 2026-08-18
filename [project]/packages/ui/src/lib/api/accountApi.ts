import { mta } from "@/lib/mta/MtaBridge";
import type { MtaResponse } from "@/types/api";
import type { Account } from "@/types/account";

export const accountApi = {
  getCurrent(): Promise<MtaResponse<Account>> {
    return mta.fetch<Account>("account.current", []);
  },
};
