import type {
  MtaFetchOptions,
  MtaFetchRequestEnvelope,
  MtaPushEventName,
  MtaResponse,
} from "@/types/api";
import { isMtaEnvironment } from "./environment";
import { MtaTransport } from "./MtaTransport";
import { BrowserDevTransport } from "./BrowserDevTransport";
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
  private readonly transport: MtaTransportLike;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly pushHandlers = new Map<string, Set<PushHandler>>();

  constructor(transport: MtaTransportLike) {
    this.transport = transport;

    this.transport.onResponse((requestId, response) => {
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

    this.transport.onPush((event, data) => {
      console.log("[mta.on] push event received", event, data);
      this.pushHandlers.get(event)?.forEach((handler) => handler(data));
    });
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

  saveCredentials(login: string, password: string): void {
    this.transport.saveCredentials(login, password);
  }

  clearCredentials(): void {
    this.transport.clearCredentials();
  }

  loadCredentials() {
    return this.transport.loadCredentials();
  }
}

const usingMtaTransport = isMtaEnvironment();
console.log("[MtaBridge] environment detected:", usingMtaTransport ? "MTA (real transport)" : "plain browser (dev transport)");

const transport: MtaTransportLike = usingMtaTransport ? new MtaTransport() : new BrowserDevTransport();

export const mta = new MtaBridge(transport);
export { isMtaEnvironment };
