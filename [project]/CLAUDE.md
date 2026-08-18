# CLAUDE.md

See `AGENTS.md` for the full set of project conventions, architecture
rules, and MTA-specific gotchas - it applies here in full.

A few things specific to how Claude Code should work in this repo:

- This is a Windows environment. The MTA resources directory tree
  (`mods/deathmatch/resources/`) uses bracketed grouping folders on disk
  - `[core]`, `[gameplay]`, `[systems]`, and this very directory,
  `[project]` - these are MTA's convention for a non-resource
  organizational folder, not resources themselves. Don't be thrown off by
  the brackets when navigating paths.
- This whole `[project]` directory (containing this file, `AGENTS.md`,
  `README.md`, `docs/`, `packages/`, `scripts/`) is deliberately NOT at
  the repository root - the repo root doubles as the MTA server's own
  runtime directory (`MTA Server.exe` and its DLLs live there), and
  nothing project-related belongs mixed in with that. Everything you'd
  normally expect at a repo root lives here instead, one level inside
  `mods/deathmatch/resources/`.
- `packages/ui` is a separate pnpm project from `[project]`'s own root -
  there is no `package.json`/workspace file directly in `[project]`
  (deliberately removed after it conflicted with a permission hook; keep
  it that way). Run `pnpm` commands from inside `packages/ui`, not
  `[project]` itself.
- When a change to `packages/ui` needs to be visible in-game, run `node
  scripts/build-ui.mjs` from `[project]` (this directory) afterward -
  this is easy to forget and `pnpm build` alone silently doesn't update
  what MTA serves. The script resolves the sibling `../[core]/core_ui/`
  path itself; you don't need to `cd` anywhere else first.
- Prefer fixing the root cause over adding a workaround, especially for
  the resource-restart-ordering class of bugs described in `AGENTS.md` -
  several of those were found live, in-game, via the user pasting F8
  console output, and each one had a specific, identifiable root cause
  (missing `addEvent`, a removed MTA function, a registration that only
  ran once instead of on every restart). If something that touches the
  CEF↔Lua bridge misbehaves, ask for the F8 console and `/browserdebug`
  console output rather than guessing further after two or three failed
  hypotheses.
