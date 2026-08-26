import type {
  MtaFetchOptions,
  MtaFetchRequestEnvelope,
  MtaPushEventName,
  MtaResponse,
} from "@/types/api";
import { isMtaEnvironment } from "./environment";
import { MtaTransport } from "./MtaTransport";
import type { MtaTransportLike } from "./Transport";
import { uuidv8 } from "../uv8";

const DEFAULT_TIMEOUT_MS = 15000;

function createRequestId(): string {
  return uuidv8();
}

interface PendingRequest {
  resolve: (response: MtaResponse<unknown>) => void;
  timeoutId: number;
}

type PushHandler = (data: unknown) => void;

class MtaBridge {
  private transport: MtaTransportLike;
  private unsubscribeResponse: (() => void) | null = null;
  private unsubscribePush: (() => void) | null = null;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly pushHandlers = new Map<string, Set<PushHandler>>();

  constructor(transport: MtaTransportLike) {
    this.transport = transport;
    this.subscribeToTransport();
  }

  private subscribeToTransport(): void {
    this.unsubscribeResponse = this.transport.onResponse((requestId, response) => {
      console.log("[mta.fetch] received response", requestId, response);

      const request = this.pending.get(requestId);
      if (!request) {
        console.warn("[mta.fetch] response for unknown/already-settled request id", requestId);
        return;
      }

      window.clearTimeout(request.timeoutId);
      this.pending.delete(requestId);
      request.resolve(response);
    });

    this.unsubscribePush = this.transport.onPush((event, data) => {
      console.log("[mta.on] push event received", event, data);
      this.pushHandlers.get(event)?.forEach((handler) => handler(data));
    });
  }

  /**
   * Swaps the active transport after construction - only used to install
   * BrowserDevTransport once its dynamic import resolves (see the bottom
   * of this file). A NoopTransport placeholder is active in the brief
   * window before that, so `mta` is safe to use synchronously from the
   * moment the module loads, same as before this became async.
   */
  _setTransport(transport: MtaTransportLike): void {
    this.unsubscribeResponse?.();
    this.unsubscribePush?.();
    this.transport = transport;
    this.subscribeToTransport();
  }

  async fetch<T>(
    endpoint: string,
    args: unknown[] = [],
    options: MtaFetchOptions = {},
  ): Promise<MtaResponse<T>> {
    const timeout = options.timeout ?? DEFAULT_TIMEOUT_MS;
    const id = createRequestId();

    const envelope: MtaFetchRequestEnvelope = {
      id,
      endpoint,
      arguments: args,
      ts: Date.now(),
    };

    console.log("[mta.fetch] sending", envelope);

    return new Promise<MtaResponse<T>>((resolve) => {
      const timeoutId = window.setTimeout(() => {
        console.warn("[mta.fetch] timed out, no response received", envelope);
        this.pending.delete(id);
        resolve({ success: false, error: { code: "REQUEST_TIMEOUT" } });
      }, timeout);

      if (options.signal) {
        options.signal.addEventListener(
          "abort",
          () => {
            window.clearTimeout(timeoutId);
            this.pending.delete(id);
            resolve({ success: false, error: { code: "REQUEST_TIMEOUT", message: "Aborted" } });
          },
          { once: true },
        );
      }

      this.pending.set(id, {
        resolve: resolve as (response: MtaResponse<unknown>) => void,
        timeoutId,
      });

      this.transport.send(envelope);
    });
  }

  on(event: MtaPushEventName | string, handler: PushHandler): void {
    if (!this.pushHandlers.has(event)) {
      this.pushHandlers.set(event, new Set());
    }
    this.pushHandlers.get(event)!.add(handler);
  }

  off(event: MtaPushEventName | string, handler: PushHandler): void {
    this.pushHandlers.get(event)?.delete(handler);
  }

  notify(eventName: string, ...args: unknown[]): void {
    this.transport.notify(eventName, ...args);
  }

  upsertAccount(login: string, password: string, rememberPassword: boolean): void {
    this.transport.upsertAccount(login, password, rememberPassword);
  }

  touchAccount(login: string): void {
    this.transport.touchAccount(login);
  }

  removeAccount(login: string): void {
    this.transport.removeAccount(login);
  }

  listAccounts() {
    return this.transport.listAccounts();
  }

  saveTrustedDeviceToken(login: string, token: string): void {
    this.transport.saveTrustedDeviceToken(login, token);
  }

  clearTrustedDeviceToken(login: string): void {
    this.transport.clearTrustedDeviceToken(login);
  }

  loadTrustedDeviceToken(login: string) {
    return this.transport.loadTrustedDeviceToken(login);
  }
}

/** No-op stand-in used only for the instant between module load and BrowserDevTransport's dynamic import resolving, in dev outside MTA. */
class NoopTransport implements MtaTransportLike {
  send(): void {}
  onResponse(): () => void {
    return () => {};
  }
  onPush(): () => void {
    return () => {};
  }
  notify(): void {}
  upsertAccount(): void {}
  touchAccount(): void {}
  removeAccount(): void {}
  listAccounts(): Promise<[]> {
    return Promise.resolve([]);
  }
  saveTrustedDeviceToken(): void {}
  clearTrustedDeviceToken(): void {}
  loadTrustedDeviceToken(): Promise<null> {
    return Promise.resolve(null);
  }
}

const usingMtaTransport = isMtaEnvironment();
console.log("[MtaBridge] environment detected:", usingMtaTransport ? "MTA (real transport)" : "plain browser (dev transport)");

export const mta = new MtaBridge(usingMtaTransport ? new MtaTransport() : new NoopTransport());

// BrowserDevTransport is dynamically imported and gated on
// NODE_ENV === "development" so webpack can statically eliminate it (and
// its mock account/credentials logic) from a production build entirely -
// a production build is always usingMtaTransport === true in practice
// (this app only ever ships inside MTA's CEF), but a stray static import
// would still have pulled the module's code into the bundle regardless.
if (!usingMtaTransport && process.env.NODE_ENV === "development") {
  void import("./BrowserDevTransport").then(({ BrowserDevTransport }) => {
    mta._setTransport(new BrowserDevTransport());
  });
}

export { isMtaEnvironment };
