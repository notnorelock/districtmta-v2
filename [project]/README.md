# district

Foundation for a Multi Theft Auto: San Andreas roleplay gamemode. This is
not a finished game mode - it is the architectural skeleton (accounts,
database abstraction, CEF bridge, notifications) that future systems
(characters, inventory, economy, jobs, factions, ...) will be built on top
of.

## Prerequisites

- An MTA:SA server install. The repository root (`district/`) doubles as
  the server's own runtime directory - `MTA Server.exe` and its DLLs live
  there directly alongside `mods/deathmatch/`, since that's where the
  server binary expects to find them. Everything that is NOT part of the
  running server (this README, `docs/`, `packages/`, `scripts/`) lives
  inside `mods/deathmatch/resources/[project]/` instead - MTA only ever
  reads `.lua`/`meta.xml`/asset files inside actual resource folders, so
  keeping the non-resource project files there too, in their own
  bracketed (non-resource) folder, keeps everything in one repository
  without the server trying to load any of it as a resource.
- [Node.js](https://nodejs.org/) 20+ for the frontend.
- [pnpm](https://pnpm.io/) for frontend package management. If it's not
  installed globally: `npm install -g pnpm` (or `corepack enable &&
  corepack prepare pnpm@latest --activate`, if your environment allows
  corepack to write to its install location).
- [Docker](https://www.docker.com/products/docker-desktop/) - runs the
  real database this repo requires (`docker-compose.yml`, see "Attaching
  a real database" below). `core` has no other way to serve
  `Database.*` calls - there is no in-memory fallback.

## Repository layout

```
district/                                  MTA server runtime root
├── MTA Server.exe, core.dll, net.dll, ...  the server binary itself
├── mods/deathmatch/resources/
│   ├── [core]/
│   │   ├── core_shared/     event names, error codes, validation rules, enums (pure data)
│   │   ├── core/            database, logging, player/account context, account domain, notifications
│   │   ├── core_ui/         generic CEF bridge - FetchBridge router, push events, browser lifecycle
│   │   ├── core_auth/       "remember me" local credential persistence + all post-login UI orchestration (auth window, spawn selection)
│   │   └── core_admin/      native dxGUI/dxDraw admin panel + reports overlay (client-only)
│   ├── [systems]/            reserved for future loosely-coupled systems
│   ├── [gameplay]/
│   │   └── gm_roleplay/     the gamemode entry resource
│   └── [project]/            <- you are here - not a resource, MTA never loads this
│       ├── packages/
│       │   └── ui/           SolidJS + TypeScript + Vite + Tailwind v4 CEF frontend
│       ├── scripts/
│       │   └── build-ui.mjs  builds packages/ui and copies it into core_ui's client/html
│       ├── docs/
│       │   ├── Architecture.md       resource responsibilities, dependency rules, account lifecycle
│       │   ├── DatabaseContract.md   exact Database.* contract a real adapter must satisfy
│       │   └── UiBridge.md           full CEF <-> MTA request/response/push protocol
│       ├── README.md         this file
│       ├── AGENTS.md         AI agent conventions/gotchas for this repo
│       └── CLAUDE.md
```

Read `docs/Architecture.md` first - in particular the section explaining
why the CEF bridge (`core_ui`) is its own resource while the database/
account/logging modules stay merged into one (`core`): MTA cannot pass Lua
closures across resource boundaries at all, so anything that needs to hand
a callback to another module has to live in the same resource as that
module, while anything that only needs to exchange plain data or react to
an event can live separately.

## MTA resource setup

1. Ensure `mods/deathmatch/resources/[core]/core_shared`,
   `mods/deathmatch/resources/[core]/core`,
   `mods/deathmatch/resources/[core]/core_ui`,
   `mods/deathmatch/resources/[core]/core_auth`,
   `mods/deathmatch/resources/[core]/core_admin`,
   `mods/deathmatch/resources/[core]/core_bootstrap`, and
   `mods/deathmatch/resources/[gameplay]/gm_roleplay` are present under
   your MTA server's `resources` directory (they already are, if you're
   working directly in this repo).
2. Startup order is handled automatically by `core_bootstrap` - it is the
   **only** one of these seven that should have `startup="1"` in
   `mtaserver.conf` (already set up that way in this repo's
   `mods/deathmatch/mtaserver.conf`). On server boot (or a manual
   `start core_bootstrap`/`refresh core_bootstrap`), it starts the other
   six itself, one at a time, waiting for each to actually finish
   starting (`onResourceStart`) before starting the next:
   ```
   core_shared -> core -> core_ui -> core_auth -> core_admin -> gm_roleplay
   ```
   This exists specifically so the order can't drift out of sync with
   `mtaserver.conf`'s own `<resource>` line order (which MTA does NOT
   guarantee reflects actual dependency needs) or get skipped entirely by
   someone restarting a single resource by hand mid-session. Run
   `/bootstrapstatus` in the F8 console (or admin chat) to check which of
   the five are currently running. To restart the whole chain (e.g. after
   pulling new Lua changes), either `restart core_bootstrap` (a restart is
   just a stop+start of the same resource - the stop half restarts every
   currently-running resource in the chain, then the start half re-checks
   order) or run `/restartchain` directly without touching
   `core_bootstrap` itself. See `core_bootstrap/server/Bootstrap.lua`'s
   module comment for the full rationale, and `docs/Architecture.md`'s
   start-order section for why this specific order matters (`core_ui`'s
   `meta.xml` declares `core` as an `<include>` dependency, `core_auth`'s
   declares `core`/`core_ui` -
   it owns all post-login UI orchestration, the auth window AND spawn
   selection - and `gm_roleplay` declares only `core_shared`/`core`: it
   has no UI knowledge and no dependency on `core_ui`/`core_auth` at all).
3. `core` requires the local MariaDB container (`docker-compose.yml`) to
   be running - see "Attaching a real database" below. Without it,
   `MySqlAdapter.connect()` fails at `core`'s startup and every
   `Database.*` call errors until it's brought up and `core` is
   restarted.

## Frontend development

All commands below assume you're inside `mods/deathmatch/resources/[project]/`
(this file's own directory), not the repository root.

```bash
cd packages/ui
pnpm install
pnpm dev
```

This starts a Vite dev server instance (`http://localhost:5173` by
default) serving the SolidJS app in a plain browser tab. Outside MTA's
CEF, the app automatically falls back to a `BrowserDevTransport` that
fakes just enough of the FetchBridge protocol (auth status/register/current)
to preview and iterate on the UI without ever launching GTA:SA - see
`packages/ui/src/lib/mta/BrowserDevTransport.ts` and
`docs/UiBridge.md`'s "Environment detection" section.

```bash
pnpm typecheck   # tsc --noEmit
pnpm build       # production build into packages/ui/dist
```

## Building the UI for MTA

`pnpm build` alone only produces `packages/ui/dist/` - it does not update
what the game actually loads. From `mods/deathmatch/resources/[project]/`
(this file's own directory):

```bash
node scripts/build-ui.mjs
```

This builds `packages/ui` and copies the output into
`mods/deathmatch/resources/[core]/core_ui/client/html/` (a sibling of
`[project]`), which is what `core_ui`'s `meta.xml`
(`<file src="client/html/..."/>`) actually ships to connecting players.
Run this after every frontend change you want visible in-game, then
restart (or refresh) the `core_ui` resource.

## Attaching a real database

The account/auth vertical slice requires a real database - there is no
in-memory fallback. This repo ships `docker-compose.yml` (in this
directory) for a local MariaDB instance - MTA's native `dbConnect("mysql",
...)` driver speaks the MySQL wire protocol, which MariaDB implements, so
no Lua-side changes are needed to point `core` at it instead of real
MySQL.

1. Start the container (Docker Desktop must be running):
   ```bash
   docker compose up -d
   ```
   This creates a `district_mariadb` container with a persistent named
   volume (`district_mariadb_data` - survives `docker compose down`,
   only removed with `down -v`), exposing port `3306` on `127.0.0.1` and
   seeding a `district` database on first run.
2. Credentials are already wired up in both places and must be kept in
   sync if you change either: `docker-compose.yml`'s
   `MARIADB_ROOT_PASSWORD`/`MARIADB_DATABASE` and
   `mods/deathmatch/resources/[core]/core/meta.xml`'s
   `MYSQL_USERNAME`/`MYSQL_PASSWORD`/`MYSQL_DATABASE`/`MYSQL_HOST`/
   `MYSQL_PORT`/`MYSQL_CHARSET` settings (currently `root` /
   `amethyst` / `district` / `127.0.0.1` / `3306` / `utf8mb4`).
3. Restart `core` (or the whole chain via `restart core_bootstrap`/
   `/restartchain`, see above) - `MySqlAdapterBootstrap.lua` connects via
   MTA's native `dbConnect` and registers `MySqlAdapter.lua` as the
   active `Database.*` adapter, then runs `Schema.migrate()` to create
   every table declared by a model
   (`core/server/database/models/Account.lua`, `Character.lua`)
   automatically - no manual `.sql` migration files to run.

To inspect the database directly: `docker exec -it district_mariadb
mariadb -u root -pamethyst district`. To stop the container without
losing data: `docker compose stop` (or `down`, which also removes the
container but keeps the named volume); `docker compose down -v` deletes
the data too.

See `docs/DatabaseContract.md` for the full `Database.*` adapter contract
and the small Active Record ORM (`core/server/orm/`) built on top of it -
`Model.lua`, `QueryBuilder.lua`, `Schema.lua`. No repository
(`AccountRepository.lua`, `CharacterRepository.lua`) or service
(`AccountService.lua`) code needs to change when switching adapters -
that's the point of the abstraction.

## Architecture summary

- **Accounts use real login/email + password authentication.** Passwords
  are hashed with MTA's native bcrypt binding (`passwordHash`/
  `passwordVerify`, `"$2y$"` format) - see `docs/Architecture.md`'s account
  lifecycle section. Account primary keys are MySQL `AUTO_INCREMENT`
  integers, not UUIDs.
- **MTA's own serial** (`getPlayerSerial(player)`, stored as `mta_serial`)
  is a "recognize this client" convenience, rebound on every successful
  login - it is explicitly **not** the authentication credential; the
  password is.
- **The browser never talks to the database.** Every CEF request goes
  through an explicit, validated, rate-limited endpoint registry
  (`FetchBridge`, in `core_ui`) - there is no mechanism for the browser to
  trigger arbitrary server-side code. See `docs/UiBridge.md`.
- **Nothing from the client is trusted.** Account id, permissions, money,
  ownership - all of it is resolved from server-side state
  (`PlayerService`), never taken from a client-supplied payload field.

## Development quality notes

This foundation is meant to actually run, not to be scaffolding with
`TODO`s scattered through it. If you hit a startup error after wiring
this into a live server, check resource start order first (`core_shared`
-> `core` -> `core_ui` -> `core_auth` -> `core_admin` -> `gm_roleplay`) and `docs/Architecture.md`'s
`GlobalResources.lua` section. Two easy-to-miss MTA gotchas that broke
this bridge during development and are worth knowing about up front:
`mta.triggerEvent(...)` from CEF requires a matching `addEvent(...)` on
the Lua side or it fails completely silently, and `toJSON(...)` always
wraps its result in a top-level array - see `docs/UiBridge.md`'s
"Two MTA gotchas" section for both.
