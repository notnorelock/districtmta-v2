import type { MtaFetchRequestEnvelope, MtaPushEventName, MtaResponse } from "@/types/api";
import type { RememberedAccount } from "@/types/account";

// MtaBridge is the only consumer of this interface - nothing else should care which
// transport (real MTA Lua vs BrowserDevTransport) is active.
export interface MtaTransportLike {
  send(envelope: MtaFetchRequestEnvelope): void;
  onResponse(handler: (requestId: string, response: MtaResponse<unknown>) => void): () => void;
  onPush(handler: (event: MtaPushEventName | string, data: unknown) => void): () => void;
  notify(eventName: string, ...args: unknown[]): void;
  upsertAccount(login: string, password: string, rememberPassword: boolean): void;
  touchAccount(login: string): void;
  removeAccount(login: string): void;
  listAccounts(): Promise<RememberedAccount[]>;
  saveTrustedDeviceToken(login: string, token: string): void;
  clearTrustedDeviceToken(login: string): void;
  loadTrustedDeviceToken(login: string): Promise<string | null>;
}
