/** Wire-level contracts for the MTA <-> CEF FetchBridge - see docs/UiBridge.md. */

/** Mirrors ErrorCodes.lua in core_shared - keep in sync manually. */
export type ApiErrorCode =
  | "INVALID_REQUEST"
  | "INVALID_ARGUMENTS"
  | "INVALID_LOGIN"
  | "INVALID_EMAIL"
  | "INVALID_PASSWORD"
  | "INVALID_CREDENTIALS"
  | "ACCOUNT_BANNED"
  | "NOT_AUTHENTICATED"
  | "ACCOUNT_NOT_FOUND"
  | "ACCOUNT_ALREADY_EXISTS"
  | "RATE_LIMITED"
  | "REQUEST_TIMEOUT"
  | "INTERNAL_ERROR"
  | "RESOURCE_UNAVAILABLE"
  | "UNKNOWN_ENDPOINT"
  | "INVALID_SPAWN"
  | "FORBIDDEN"
  | "REPORT_NOT_FOUND"
  | "PLAYER_NOT_FOUND";

export interface ApiError {
  code: ApiErrorCode;
  message?: string;
}

export type MtaResponse<T> =
  | { success: true; data: T }
  | { success: false; error: ApiError };

export interface MtaFetchOptions {
  timeout?: number;
  signal?: AbortSignal;
}

/** The envelope sent from the browser into MTA client-side Lua. */
export interface MtaFetchRequestEnvelope {
  id: string;
  endpoint: string;
  arguments: unknown[];
  ts: number;
}

/** Push events delivered unsolicited by the server, outside the RPC channel. */
export type MtaPushEventName =
  | "account.updated"
  | "account.resolved"
  | "notification.created"
  | "ui.open"
  | "ui.close"
  | "loading.progress"
  | "hud.updated"
  | "overlay.show"
  | "overlay.hide";
