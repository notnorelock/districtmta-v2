# vite-plugin-jsvm

Replaces this package's own `index` chunk with a **JSVM bytecode-VM obfuscated**
equivalent during `vite build`. `vendor.js` (node_modules), `rolldown-runtime.js`,
CSS, fonts and images are **not** touched.

## How it works

1. Runs in `generateBundle` (`enforce: "post"`) — after Rolldown has produced the
   final chunks, resolved `import.meta.*`, split vendor and emitted assets.
2. For each chunk in `include` (default `["index"]`), POSTs its code to a running
   JSVM compile server (`/api/compile`) and swaps in the returned module.
3. The chunk's `import "./vendor.js"` / `import "./rolldown-runtime.js"` are kept
   verbatim. The JSVM output re-emits them as real `import * as`, so the browser
   still loads those chunks **unobfuscated** and the VM'd code calls into them
   across a normal function-call boundary. Runtime model:

   ```
   dist/assets/index.js   ← obfuscated: [ import * as _v from "./vendor.js" ] + VM + bytecode
   dist/assets/vendor.js  ← plain SolidJS/@kobalte/… , runs natively
   ```

## Requirements

- A **running JSVM compile server**. In the `jsvm-main` project: `npm run dev-api`
  (listens on `:3010`). Override with `JSVM_ENDPOINT`.
- The chunk must be pure JS — no surviving CSS/asset imports. This project's Vite
  config already inlines CSS (`cssCodeSplit: false`) and turns assets into URLs,
  so `index` is clean. The plugin skips (or, with `strict`, fails) any chunk that
  still imports a non-JS module.

## Options

| option | default | meaning |
|---|---|---|
| `endpoint` | `http://127.0.0.1:3010/api/compile` | JSVM compile server |
| `include` | `["index"]` | chunk names (Rolldown `[name]`) to obfuscate |
| `strict` | `false` | fail the build on a compile error instead of leaving the chunk plain |
| `disabled` | `false` | skip the plugin entirely |
| `timeoutMs` | `120000` | per-chunk request timeout |

## Env toggles (wired in `vite.config.ts`)

| env | effect |
|---|---|
| `JSVM_OBFUSCATE=0` | disable the plugin for this build |
| `JSVM_ENDPOINT=…` | point at a different compile server |
| `JSVM_STRICT=1` | make a compile failure fail the build |
| `KEEP_DEBUG_OUTPUT=1` (a `--dev` build) | disables the plugin (same gate as the console-strip skip) |

It replaced the old `js-confuser` post-build pass, which has been removed from
`scripts/build-ui.mjs` and `packages/ui/package.json`.

## Caveats

- **Perf**: every function call in `index` becomes interpreted bytecode. Fine for
  the auth/spawn/dashboard UI; keep hot per-frame render paths (the smoke shader,
  the live map) out of obfuscated modules or profile them.
- **`import.meta.url`**: the VM stubs it as `""`. This build only uses it as the
  base of a `new URL(absoluteUrl, import.meta.url)` call where arg 1 is already
  absolute (Vite's `base` rewrote it), so `""` is harmless. If a future change
  uses `import.meta.url` as a real relative base, that breaks — the plugin does
  not currently detect it.
- **No cross-obfuscated-module graph**: only obfuscate one leaf chunk (`index`).
  Two obfuscated chunks importing each other would each boot their own VM.
