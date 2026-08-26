import type { MtaFetchRequestEnvelope, MtaPushEventName, MtaResponse } from "@/types/api";
import type { SavedCredentials } from "@/types/account";

// MtaBridge is the only consumer of this interface - nothing else should care which
// transport (real MTA Lua vs BrowserDevTransport) is active.
export interface MtaTransportLike {
  send(envelope: MtaFetchRequestEnvelope): void;
  onResponse(handler: (requestId: string, response: MtaResponse<unknown>) => void): () => void;
  onPush(handler: (event: MtaPushEventName | string, data: unknown) => void): () => void;
  notify(eventName: string, ...args: unknown[]): void;
  saveCredentials(login: string, password: string): void;
  clearCredentials(): void;
  loadCredentials(): Promise<SavedCredentials | null>;
  saveTrustedDeviceToken(token: string): void;
  clearTrustedDeviceToken(): void;
  loadTrustedDeviceToken(): Promise<string | null>;
}
