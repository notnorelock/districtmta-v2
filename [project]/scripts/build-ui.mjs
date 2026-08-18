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
import { existsSync, mkdirSync, rmSync, cpSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

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

console.log("[build-ui] Building packages/ui...");
const webpackBin = path.join(uiDir, "node_modules", "webpack-cli", "bin", "cli.js");
const build = spawnSync(process.execPath, [webpackBin, "--mode", "production"], { cwd: uiDir, stdio: "inherit" });

if (build.status !== 0) {
  console.error("[build-ui] webpack build failed.");
  process.exit(build.status ?? 1);
}

if (!existsSync(distDir)) {
  console.error(`[build-ui] Expected build output at ${distDir}, but it does not exist.`);
  process.exit(1);
}

console.log(`[build-ui] Clearing ${targetDir}...`);
if (existsSync(targetDir)) {
  rmSync(targetDir, { recursive: true, force: true });
}
mkdirSync(targetDir, { recursive: true });

console.log(`[build-ui] Copying dist -> ${targetDir}...`);
cpSync(distDir, targetDir, { recursive: true });

console.log("[build-ui] Done. Restart (or refresh) the core_ui resource in-game to pick up the new build.");
