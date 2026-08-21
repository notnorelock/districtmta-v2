#!/usr/bin/env node

/**
 * Builds packages/ui and copies the production bundle into the MTA
 * "core_ui" resource's client/html directory, which is what meta.xml's
 * <file src="client/html/index.html" /> and <file src="client/html/assets/*" />
 * tags actually ship to players. Run this after every frontend change
 * intended for in-game use - `pnpm dev` alone only serves the UI to a
 * plain browser tab and never touches this directory.
 */
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, cpSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

// --dev keeps webpack's own "production" --mode (still required - it's
// what makes publicPath the fixed "http://mta/local/client/html/" every
// asset reference needs to actually resolve once this ships into
// core_ui/client/html; webpack's "development" mode's publicPath: "auto"
// is only correct for pnpm dev's own localhost server, and would 404
// every font/texture/CSS reference here - see webpack.config.js's own
// publicPath comment), but passes --env debug so TerserPlugin skips
// drop_console/drop_debugger (see keepDebugOutput in webpack.config.js),
// and skips the js-confuser obfuscation pass below - use this while
// chasing a bug through /browserdebug's console, where a normal
// production build's stripped console.* calls and concealed/mangled
// output make the actual failure unreadable. Never pass --dev for a
// build meant to ship.
const isDevBuild = process.argv.includes("--dev");

// This file lives at mods/deathmatch/resources/[project]/scripts/build-ui.mjs.
// projectDir is "[project]/" itself (packages/ui lives directly under it);
// resourcesDir is "mods/deathmatch/resources/" (one level up - "[project]"
// is a direct sibling of "[core]"/"[gameplay]" inside resources/). Both
// bracketed names are MTA's convention for a non-resource organizational
// folder, not resources themselves - MTA never reads anything under
// "[project]" at all.
const projectDir = fileURLToPath(new URL("..", import.meta.url));
const resourcesDir = path.join(projectDir, "..");
const uiDir = path.join(projectDir, "packages", "ui");
const distDir = path.join(uiDir, "dist");
const targetDir = path.join(resourcesDir, "[core]", "core_ui", "client", "html");

console.log(`[build-ui] Building packages/ui${isDevBuild ? " (--env debug: console.* kept)" : ""}...`);
const webpackBin = path.join(uiDir, "node_modules", "webpack-cli", "bin", "cli.js");
const webpackArgs = ["--mode", "production"];
if (isDevBuild) {
  webpackArgs.push("--env", "debug");
}
const build = spawnSync(process.execPath, [webpackBin, ...webpackArgs], { cwd: uiDir, stdio: "inherit" });

if (build.status !== 0) {
  console.error("[build-ui] webpack build failed.");
  process.exit(build.status ?? 1);
}

if (!existsSync(distDir)) {
  console.error(`[build-ui] Expected build output at ${distDir}, but it does not exist.`);
  process.exit(1);
}

// Post-processes the already-minified/Terser'd output with js-confuser -
// this is on top of, not instead of, webpack.config.js's own
// mode: "production" minification. Deliberately a MODERATE preset, not
// js-confuser's own "high": renaming + string concealing only.
// controlFlowFlattening is left off on purpose - it's the one option
// js-confuser's own docs flag as "significantly impacts performance",
// and this bundle runs inside MTA's CEF browser rendering the HUD every
// frame, not a page that loads once. renameGlobals is off too (also
// per js-confuser's own guidance for "web-related scripts") - webpack's
// output relies on a few real global bindings (window.mta, __mtaSessionKey,
// etc. - see MtaTransport.ts) that must keep their real names to still
// work at runtime.
const JS_CONFUSER_OPTIONS = {
  target: "browser",
  preset: false,
  renameVariables: false,
  renameGlobals: false,
  renameLabels: true,
  identifierGenerator: "mangled",
  stringConcealing: true,
  controlFlowFlattening: true,
  compact: true,
  lock: {
    integrity: true,
  }
};

if (isDevBuild) {
  console.log("[build-ui] --dev: skipping js-confuser obfuscation.");
} else {
  console.log("[build-ui] Obfuscating built JS with js-confuser...");
  // [project] has no package.json of its own (see CLAUDE.md) - js-confuser
  // is only installed under packages/ui's own node_modules, so it's
  // imported from there explicitly by path rather than as a bare specifier.
  const { default: JsConfuser } = await import(
    pathToFileURL(path.join(uiDir, "node_modules", "js-confuser", "dist", "index.js"))
  );
  const jsAssetsDir = path.join(distDir, "assets");
  // vendor.js (node_modules: solid-js, @kobalte/core, lucide-solid, ...) is
  // deliberately skipped - nothing project-specific worth hiding lives
  // there, and obfuscating it roughly tripled its size (103KB -> 293KB)
  // for no real benefit, on a bundle that runs inside CEF rendering the
  // HUD every frame. Only index.js (this project's own source) is worth
  // the size/runtime cost.
  const jsFiles = existsSync(jsAssetsDir) ? readdirSync(jsAssetsDir).filter((name) => name === "index.js") : [];

  for (const fileName of jsFiles) {
    const filePath = path.join(jsAssetsDir, fileName);
    const source = readFileSync(filePath, "utf-8");

    try {
      const { code } = await JsConfuser.obfuscate(source, JS_CONFUSER_OPTIONS);
      writeFileSync(filePath, code, "utf-8");
      console.log(`[build-ui] Obfuscated ${fileName}`);
    } catch (error) {
      console.error(`[build-ui] js-confuser failed on ${fileName}:`, error);
      process.exit(1);
    }
  }
}

console.log(`[build-ui] Clearing ${targetDir}...`);
if (existsSync(targetDir)) {
  rmSync(targetDir, { recursive: true, force: true });
}
mkdirSync(targetDir, { recursive: true });

console.log(`[build-ui] Copying dist -> ${targetDir}...`);
cpSync(distDir, targetDir, { recursive: true });

console.log("[build-ui] Done. Restart (or refresh) the core_ui resource in-game to pick up the new build.");
