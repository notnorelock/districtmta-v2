import type { Plugin } from "vite";

/**
 * Replaces selected build chunks with JSVM-obfuscated equivalents.
 *
 * How it fits the build:
 *   - runs in `generateBundle`, after Vite/Rolldown has produced the final
 *     chunks, resolved `import.meta.*`, split vendor, emitted assets
 *   - for each chunk whose name matches `include`, POSTs its code to the JSVM
 *     `/api/compile` endpoint and swaps in the returned module
 *   - `import` statements to sibling chunks (`./vendor.js`, `./rolldown-runtime.js`)
 *     are preserved verbatim: the JSVM output re-emits them as real
 *     `import * as`, so the browser still loads those chunks UNOBFUSCATED and the
 *     VM'd code calls into them across a normal function-call boundary
 *
 * What it deliberately does NOT touch: `vendor` (node_modules), the rolldown
 * runtime, CSS, fonts, images, or any chunk not in `include`.
 */
export interface JsvmPluginOptions {
  /**
   * Endpoint of a running JSVM compile server (the `jsvm-main` project's
   * `npm run dev-api`). Default: http://127.0.0.1:3010/api/compile
   */
  endpoint?: string;
  /**
   * Chunk names (without extension) to obfuscate. Default: ["index"].
   * A chunk name is what Rolldown puts in `[name]` — for this project's config
   * that's "index" for app code and "vendor" for node_modules.
   */
  include?: string[];
  /**
   * When true, a chunk that fails to compile fails the whole build.
   * When false (default), it's left un-obfuscated and a warning is logged.
   */
  strict?: boolean;
  /** Skip entirely (e.g. for a --dev build). Default: false. */
  disabled?: boolean;
  /** Request timeout in ms. Default: 120000. */
  timeoutMs?: number;
  /**
   * Emit a VM with a diagnostic hook: when a call target turns out not to be a
   * function it logs the receiver / key / arg shapes + a stack trace to the
   * console before throwing. Slightly larger output; for chasing a bug in-game.
   */
  debug?: boolean;
}

interface CompileResponse {
  disasm?: string;
  code?: string;
  format?: "module" | "script";
  error?: string;
}

async function compile(
  endpoint: string,
  source: string,
  timeoutMs: number,
  debug: boolean,
): Promise<CompileResponse> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: source, is_production: true, debug }),
      signal: ctrl.signal,
    });
    if (!res.ok) {
      let detail = "";
      try {
        detail = ((await res.json()) as CompileResponse).error ?? "";
      } catch {
        /* non-JSON body */
      }
      return { error: `HTTP ${res.status}${detail ? ` — ${detail}` : ""}` };
    }
    return (await res.json()) as CompileResponse;
  } catch (e: any) {
    if (e?.name === "AbortError") return { error: `timed out after ${timeoutMs}ms` };
    return { error: String(e?.message ?? e) };
  } finally {
    clearTimeout(t);
  }
}

export default function jsvmObfuscate(options: JsvmPluginOptions = {}): Plugin {
  const endpoint = options.endpoint ?? "http://127.0.0.1:3010/api/compile";
  const include = new Set(options.include ?? ["index"]);
  const strict = options.strict ?? false;
  const disabled = options.disabled ?? false;
  const timeoutMs = options.timeoutMs ?? 120_000;
  const debug = options.debug ?? false;

  return {
    name: "jsvm-obfuscate",
    apply: "build",
    // run after other transforms; `post` keeps us at the end of the chain
    enforce: "post",

    async generateBundle(_outputOptions, bundle) {
      if (disabled) {
        this.warn("[jsvm] disabled — chunks left un-obfuscated");
        return;
      }

      const targets = Object.values(bundle).filter(
        (c): c is typeof c & { type: "chunk" } =>
          c.type === "chunk" && include.has(c.name),
      );

      if (targets.length === 0) {
        this.warn(
          `[jsvm] no chunks matched include=[${[...include].join(", ")}] — nothing obfuscated`,
        );
        return;
      }

      for (const chunk of targets) {
        // Guard: the JSVM module wrapper re-emits imports as `import * as`, which
        // the browser can only satisfy for real ES modules. A CSS/asset import
        // that survived to here would break — bail on this chunk.
        const badImport = chunk.imports.find((s) => /\.(css|scss|sass|less|png|jpe?g|gif|svg|webp|woff2?|ttf|otf)$/i.test(s));
        if (badImport) {
          const msg = `[jsvm] chunk "${chunk.fileName}" imports a non-JS module (${badImport}); skipping`;
          if (strict) this.error(msg);
          this.warn(msg);
          continue;
        }

        const sourceLen = chunk.code.length;
        const res = await compile(endpoint, chunk.code, timeoutMs, debug);

        if (res.error || !res.code) {
          const msg = `[jsvm] failed to obfuscate "${chunk.fileName}": ${res.error ?? "empty response"}`;
          if (strict) this.error(msg);
          this.warn(`${msg} — chunk left un-obfuscated`);
          continue;
        }

        chunk.code = res.code;
        // the obfuscated form is a real module regardless of the original shape
        const ratio = ((res.code.length / sourceLen) * 100).toFixed(0);
        this.info(
          `[jsvm] ${chunk.fileName}: ${sourceLen} → ${res.code.length} bytes (${ratio}%), format=${res.format ?? "?"}`,
        );

        if (debug && res.disasm) {
          this.emitFile({
            type: "asset",
            fileName: `${chunk.fileName}.disasm.txt`,
            source: res.disasm,
          });
          this.info(`[jsvm] disassembly emitted as ${chunk.fileName}.disasm.txt`);
        }
      }
    },
  };
}
