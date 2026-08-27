import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import solid from "vite-plugin-solid";

const rootDir = fileURLToPath(new URL(".", import.meta.url));
const srcDir = path.join(rootDir, "src");

// Read once at build time - "unknown" outside a git checkout (e.g. a
// packaged release with no .git/) rather than failing the build.
function getBuildCommit() {
  try {
    return execSync("git rev-parse --short HEAD", { cwd: rootDir }).toString().trim();
  } catch {
    return "unknown";
  }
}

export default defineConfig(({ command }) => {
  const isBuild = command === "build";
  // Set by [project]/scripts/build-ui.mjs's --dev flag - keeps
  // console.*/debugger statements in the output while chasing a bug
  // through /browserdebug's console, where a normal production build's
  // stripped output makes the actual failure unreadable. Never set for a
  // build meant to ship.
  const keepDebugOutput = process.env.KEEP_DEBUG_OUTPUT === "1";

  return {
    plugins: [solid()],

    resolve: {
      alias: {
        "@": srcDir,
      },
    },

    // Absolute in a real build, not "/" - every asset reference (CSS
    // url(), font-face, new URL(..., import.meta.url) for textures)
    // resolves from this ONE fixed root regardless of which file
    // references it or where that file itself ends up. MTA serves this
    // resource's client files under exactly this fixed local-scheme path
    // (see meta.xml's <file> entries under core_ui/client/html/), so it's
    // safe to hardcode - but only for the real MTA build. `pnpm dev`
    // serves this same bundle from localhost:5173 in a plain browser tab
    // (see lib/mta/environment.ts's isMtaEnvironment split), where that
    // absolute mta:// URL would never resolve, so dev keeps Vite's own
    // default "/" (relative to the dev server's own origin).
    base: isBuild ? "http://mta/local/client/html/" : "/",

    define: {
      __BUILD_COMMIT__: JSON.stringify(getBuildCommit()),
      // No @types/node dependency and no real Node process object at
      // runtime (see globals.d.ts) - this string-replaces every
      // process.env.NODE_ENV reference at build time, same as webpack's
      // DefinePlugin did, so MtaBridge.ts's dev-transport gate still
      // statically eliminates BrowserDevTransport from a production build.
      "process.env.NODE_ENV": JSON.stringify(isBuild ? "production" : "development"),
    },

    css: {
      modules: {
        // Matches css-loader's old namedExport: false - `import styles
        // from "./X.module.scss"; styles.root`, not named imports -
        // matching the globals.d.ts ambient module declaration.
        localsConvention: "camelCaseOnly",
        generateScopedName: isBuild ? "[hash:base64:8]" : "[name]__[local]",
      },
    },

    // Strips every console.*/debugger statement entirely (not just
    // silencing it - the call expression and its arguments are removed
    // from the output, so nothing the app logs - including any string
    // that might leak internal detail - survives into the shipped
    // bundle). Skipped for a --dev build (see keepDebugOutput above) so
    // /browserdebug's console still shows this app's own
    // console.log/error calls.
    esbuild: {
      drop: isBuild && !keepDebugOutput ? (["console", "debugger"] as const) : [],
    },

    build: {
      outDir: "dist",
      assetsDir: "assets",
      cssCodeSplit: false,
      target: "esnext",
      rollupOptions: {
        output: {
          // A single browser instance loads this bundle once - no content
          // hashing needed, keep filenames stable and simple to reason
          // about, matching the previous webpack build's output shape.
          entryFileNames: "assets/[name].js",
          chunkFileNames: "assets/[name].js",
          assetFileNames: "assets/[name][extname]",
          // node_modules split into its own "vendor" chunk, separate from
          // app code in "index" - vendor code (solid-js, @kobalte/core,
          // ...) changes far less often than this project's own source,
          // matching the previous webpack build's splitChunks setup.
          manualChunks(id) {
            if (id.includes("node_modules")) {
              return "vendor";
            }
          },
        },
      },
    },

    server: {
      port: 5173,
    },
  };
});
