# Architecture

This document explains how the project is organized, why the MTA resources
are split the way they are, how the account/authentication flow works end
to end, and the conventions to follow when adding new systems.

## Repository layout

The repository root (`district/`) doubles as the MTA server's own runtime
directory - `MTA Server.exe` and its DLLs live there directly. Everything
project-related (this doc, source, scripts) therefore lives one level
down, inside `mods/deathmatch/resources/[project]/` - its own bracketed,
non-resource folder, so MTA never tries to load any of it. The actual MTA
Lua resources are its siblings, also bracketed grouping folders:

```
district/                                   MTA server runtime root
├── MTA Server.exe, core.dll, net.dll, ...
├── mods/deathmatch/resources/
│   ├── [core]/                   bracketed = MTA's non-resource grouping folder
│   │   ├── core_bootstrap/      startup="1" in mtaserver.conf - starts everything else, in order (see below)
│   │   ├── core_shared/         constants only - Events, ErrorCodes, ValidationRules, Enums
│   │   ├── core/                database, logging, player/account context, account domain, notifications
│   │   ├── core_ui/             generic CEF bridge - FetchBridge router, push events, browser lifecycle
│   │   ├── core_loading/        gates Events.LOADING_READY per player until the server chain AND that player's CEF are both ready
│   │   ├── core_auth/           "remember me" local credential persistence + all post-login UI orchestration (auth window, spawn selection)
│   │   └── core_admin/          client-only native dxGUI/dxDraw admin panel + reports overlay (the duty/report/penalty business logic itself lives in core)
│   ├── [systems]/                independent gameplay-adjacent systems (empty for now)
│   ├── [gameplay]/
│   │   └── gm_roleplay/         the gamemode entry resource (type="gamemode") - server-only, just spawnPlayer
│   └── [project]/                <- this doc's own directory, NOT an MTA resource
│       ├── packages/
│       │   └── ui/               SolidJS + TypeScript + Webpack + Tailwind v4 CEF frontend
│       ├── scripts/
│       │   └── build-ui.mjs      builds packages/ui and copies dist/ into ../[core]/core_ui/client/html
│       ├── docs/                 this file, DatabaseContract.md, UiBridge.md
│       └── README.md
```

## Why the split is `core_shared` / `core` / `core_ui` (not more, not fewer)

MTA cannot pass a Lua function (closure) across a resource boundary,
**in either direction, through any mechanism**:

- `exports.resourceName:fn(args)` - confirmed against MTA server source
  (`CLuaArgument::Read`): a `LUA_TFUNCTION` value is marshalled to `nil`,
  including function fields nested inside a table. This is true for
  **both call arguments and return values** - a table returned by an
  exported function loses its function fields the same way a table passed
  as an argument does.
- `triggerEvent`/`triggerClientEvent`/`triggerServerEvent` - same
  underlying `CLuaArgument` marshalling, so a table like `{ success =
  function() ... end }` handed to `triggerEvent` arrives with `success`
  as `nil` on the other side, silently.

This single fact drives the whole resource boundary design:

- **Modules that pass callbacks to each other constantly** (the database
  layer, account service orchestration, endpoint handler registration)
  have to live in the **same resource**, because there is no way to
  relay a callback-based API across a boundary without rebuilding it as
  a manual request/response protocol with correlation IDs for every
  single call.
- **Modules that only exchange plain data, or need to react to something
  happening (not hand over a callback)**, can live in separate resources
  - `exports` for one-shot plain-data calls, plain MTA custom events
  (`addEvent`/`triggerEvent`/`addEventHandler`) for "notify me when X
  happens," since the event *registry* is engine-global even though event
  *arguments* still can't carry live functions.

Concretely:

- **`core_shared`**: pure data (event names, error codes, validation
  constants). No closures anywhere, so plain `exports` getters work
  without any special handling - see the `ValidationRules` exception
  below.
- **`core`**: `Database.*`, the ORM (`Model`/`QueryBuilder`/`Schema`), the
  account models/repositories, `AccountService`, `PlayerService`,
  `Logger`, `SecurityService`, `NotificationService`. These pass callbacks
  to each other on nearly every call (`AccountService.register(mtaSerial,
  input, onSuccess, onError)` chains through several nested async
  repository/bcrypt calls, for example) - splitting this further would
  mean rebuilding every one of those chains as a correlation-ID relay for
  no organizational benefit, since these modules always change together
  anyway.
- **`core_ui`**: the CEF bridge - `FetchBridge` (the browser-facing
  request router), `PushService`, `BrowserManager`, `Transport`. This
  resource is **domain-agnostic** - it has no idea `auth.register` or
  `account.current` exist. It only knows "an endpoint name has metadata
  (authenticated, rate limit) and something, somewhere, is listening for
  `endpoint:<name>`." This is what makes it possible for `core_ui` to be
  its own resource despite `core` owning every actual endpoint handler:
  the handler closure never crosses the boundary - only the metadata
  registration and the final plain-data response do (see "FetchBridge
  across the core/core_ui boundary" below).

`gm_roleplay` and future `systems/*`/`gameplay/*` resources talk to
`core`/`core_ui` the same way `core` and `core_ui` talk to each other:
exports for plain data, events for "notify me."

**The one hard rule for extending the project:** if a new piece of
functionality needs to hand a *callback* to another module, that module
must live in the same resource as the thing calling it. If two resources
only need to exchange plain data or react to something happening,
exports/events are fine and preferred, for keeping resources
independently restartable and organizationally separate.

### FetchBridge across the core/core_ui boundary

`FetchBridge` lives in `core_ui`, but every actual endpoint (today:
`auth.status`, `auth.register`, `account.current`) is owned and handled
by `core`. This works without ever crossing a closure across the
boundary:

```
core/server/accounts/AccountEndpoints.lua (owns the handler closure)
     |
     | 1. exports.core_ui:fetchBridgeRegisterMeta(name, {authenticated, rateLimit})
     |    -- plain data only: booleans, numbers, strings
     v
core_ui/server/FetchBridge.lua (stores metadata, has no handler)
     |
     | (later, when a browser request for that endpoint arrives)
     | 2. triggerEvent("endpoint:" .. name, resourceRoot, requestId, player, payload)
     |    -- plain data only: requestId is a string, player is an element
     |    -- (elements survive the marshalling boundary fine - only
     |    -- functions/coroutines don't), payload is plain JSON-shaped data
     v
core/server/accounts/AccountEndpoints.lua's addEventHandler("endpoint:" .. name, ...)
     |
     | (handler runs locally in core, can call AccountService etc. freely)
     | 3. exports.core_ui:fetchBridgeRespond(requestId, response)
     |    -- plain data only: response is {success, data} or {success, error}
     v
core_ui/server/FetchBridge.lua looks up the pending request by requestId,
     triggerClientEvent(...) sends it to the browser
```

Every value crossing the `core` ↔ `core_ui` boundary in both directions
is plain data - no step ever hands a function value across. See
`docs/UiBridge.md` for the full protocol including the CEF ↔ Lua leg.

## MTA resource fundamentals this project relies on

- Every resource has its own isolated Lua environment. Globals set in one
  resource's scripts are invisible to another resource's scripts.
- `<include resource="..."/>` in meta.xml is a **start-order dependency
  declaration only**. It does not share code, globals, or anything else.
- `exports.resourceName:functionName(...)` only resolves **flat top-level
  global function names** declared via `<export function="functionName"
  type="server|client|shared"/>` in the exporting resource's meta.xml. It
  cannot address a dotted path like `Database.query` directly - see
  `GlobalResources.lua` files for how this project bridges that gap.
- Custom events (`addEvent`/`triggerEvent`/`addEventHandler`) are
  engine-global: any running resource can trigger an event any other
  resource registered, regardless of which resource called `addEvent`
  first. This is what lets `core_auth`'s `AuthUiController.lua` and
  `SpawnUiController.lua` both independently react to
  `Events.PLAYER_ACCOUNT_RESOLVED`, and what lets `core_ui`'s
  `FetchBridge` dispatch to `core`'s endpoint handlers, without exports
  plumbing for the handler itself.
- `mta.triggerEvent(...)` called from CEF browser JavaScript **requires**
  the target event name to be registered with `addEvent(...)` on the
  client Lua side first - exactly like `triggerClientEvent`/
  `triggerServerEvent` - but unlike those, calling it against an
  unregistered event name fails **completely silently**: no Lua error,
  no JS error, nothing. This is easy to miss; every browser→Lua event in
  this project (`ui:fetchData`, `ui.ready`) has an explicit `addEvent`
  call directly above its `addEventHandler` with a comment explaining why.
- `toJSON(value)` always wraps its result in a top-level JSON array, even
  for a single non-array value - documented MTA behavior, since the same
  serializer backs event/export argument lists. Any Lua code that embeds
  `toJSON(...)` output directly into a JavaScript string (e.g. via
  `executeBrowserJavascript`) must strip the outer `[ ]` first (see the
  `toJsonValue` helper duplicated in `core_ui/client/ui/Transport.lua` and
  `BrowserManager.lua`) or the browser receives `[value]` instead of
  `value`.

### The `GlobalResources.lua` pattern

Because globals don't cross resource boundaries, every resource that
consumes another resource's exports has its own `server/GlobalResources.lua`
(and `client/GlobalResources.lua` where relevant), loaded as the **first**
script in meta.xml. It installs a `setmetatable(_G, { __index = ... })`
hook that lazily resolves a small, explicit set of global names (e.g.
`Events`, `PlayerService`, `PushService`) to that resource's own local
wrapper around the target resource's exports. If the target resource
isn't running, the global resolves to `false` (not `nil`), so `if not
PlayerService then ...` reads naturally everywhere.

`core_shared`'s constant tables (`Events`, `ErrorCodes`, `Enums`) are
exposed as **getter exports** (`getEvents()`, ...) rather than the tables
themselves, because exports can only be flat functions -
`GlobalResources.lua` calls the getter once and caches the result.

`ValidationRules` and `ElementData` are special-cased further: both are
the `core_shared` tables with function fields (`ValidationRules.
isValidLogin`/etc.; `ElementData.accountField`). Since exports strip
function fields from returned tables too, `getValidationRules()`/
`getElementData()` return **only the constant fields**
(`LOGIN_MIN_LENGTH`, `EMAIL_PATTERN`, ...; `ElementData.Player.*`/
`ElementData.Account.*`), and each method is exported as its own flat
function (`validationRulesIsValidLogin`, `elementDataAccountField`, ...).
Every consuming `GlobalResources.lua` that needs one stitches both back
into one local table via a metatable, so call sites everywhere keep
reading `ValidationRules.isValidLogin(login)`/`ElementData.Player.ADMIN`
unchanged.

`ElementData` (`core_shared/shared/ElementData.lua`) is the canonical
registry of every `setElementData`/`getElementData`/`removeElementData`
key used across resources (`ElementData.Player.LOGGED/SPAWNED/ADMIN/ID/
SKIN/SESSION_KEY`, `ElementData.Account.PREMIUM/MUTE`) - same "declare it
once, never a raw string literal at the call site" reasoning as
`Events.lua`. `ElementData.accountField(name)` builds the one dynamic
exception: `core_auth/server/AuthUiController.lua` mirrors most of an
account row's own columns onto `"account:<column>"` element data at
login time (`account:id`, `account:role`, ...) rather than one constant
per column, since the column set is defined by the `accounts` table
schema, not hand-enumerated here.

See `core/server/GlobalResources.lua` and `core_ui/server/GlobalResources.lua`
for concrete examples. `gameplay/gm_roleplay/server/GlobalResources.lua`
proxies a narrower set (no `ValidationRules`/`ErrorCodes` - `gm_roleplay`
has no use for them) but follows the same pattern - see the resource
responsibility table below for what each resource actually needs.

## Resource responsibilities

| Resource | Type | Responsibility |
|---|---|---|
| `core_bootstrap` | `script` | The only project resource with `startup="1"` in `mtaserver.conf`. On start (fresh boot or a plain `start core_bootstrap`), starts the other five itself, in order, waiting for each to actually finish starting before starting the next. On stop (the first half of what `restart core_bootstrap` does under the hood - MTA has no separate "restart" event, a restart is just stop then start of the same resource), explicitly `restartResource`s every currently-running resource in the chain, in order, so restarting `core_bootstrap` actually restarts everything downstream instead of a no-op skip; `/restartchain` triggers the same restart pass without touching `core_bootstrap` itself. See "Start order" below and `core_bootstrap/server/Bootstrap.lua`'s module comment. Has no other responsibility and no `<include>`s (it only calls the engine's own `startResource`/`restartResource`, not any project export). |
| `core_shared` | `script` | Event names, error codes, validation rules, enums, and small cross-resource helpers with no state of their own (`successResponse`/`errorResponse` FetchBridge envelope builders - see `Registry.lua`). Pure data/stateless functions, no privileged logic. |
| `core` | `script` | Database abstraction + ORM (`Model`/`QueryBuilder`/`Schema`) + repositories, logging, player/account runtime context, security reporting hook, per-player session key issuance (for `core_ui`'s payload obfuscation), account domain (bcrypt password hashing, registration/login, endpoint handlers), notifications. |
| `core_ui` | `script` | Domain-agnostic CEF bridge: FetchBridge request router (validation, auth check, rate limiting, dispatch), push event channel, browser lifecycle (single long-lived CEF instance, input/cursor management), payload obfuscation for the browser-facing leg (see `docs/UiBridge.md`'s "Payload obfuscation" section - transport obfuscation, not encryption). Also tracks per-player browser readiness (`UiState.isBrowserReady`, exported as `uiStateIsBrowserReady` - backed by `Events.BROWSER_READY`), which `core_loading` polls. |
| `core_loading` | `script` | Gates `Events.LOADING_READY` per player until BOTH `core_bootstrap`'s server-side chain has finished (`exports.core_bootstrap:bootstrapIsChainReady()`) AND that specific player's CEF has reported ready (`exports.core_ui:uiStateIsBrowserReady(player)`) - see `LoadingGate.lua`. Exists so a player is never told to open the auth window before the CEF bridge (or the rest of the resource chain) is actually ready to receive it - see "Loading gate" below. |
| `core_auth` | `script`, server + client | Owns essentially all post-login UI orchestration - "which named window is open right now, and why": (1) "remember me" local credential persistence (`CredentialStore.lua`/`CredentialTransport.lua`) - `core_ui/client/ui/Transport.lua` forwards the relevant browser events here (as plain custom events, never a closure) after verifying they came from the tracked browser element, and `core_auth` calls back into `core_ui`'s `uiExecuteInBrowser`/`uiObfuscateForBrowser`/`uiDeobfuscateFromBrowser` exports rather than touching the browser element or `SessionKeyState` directly (see "Remember me" below); (2) auth UI AND spawn-select UI open/close orchestration, both handled together in `AuthUiController.lua`/`AuthUiClient.lua` - listens for `Events.LOADING_READY`/`Events.PLAYER_ACCOUNT_RESOLVED` and drives `UI.open`/`UI.close` for both windows via `Events.AUTH_BEGIN_AUTHENTICATION`/`Events.AUTH_SUCCESS_AUTHENTICATION` (the latter only means "login/register succeeded, close the auth window" - not "the player is in the game world", which still waits on spawn selection) and `Events.SPAWN_SELECT_OPEN`/`_CLOSE`, backed by a static location list and two FetchBridge endpoints (`SpawnLocations.lua`/`SpawnEndpoints.lua`'s `spawn.list`/`spawn.select`, registered the same way `AccountEndpoints.lua` registers `auth.*`). `spawn.select` calls `exports.gm_roleplay:gameplayEnterWorld(player, location)` (a one-hop, plain-data call) to actually spawn the player, then closes its own window - see the account lifecycle diagram below. |
| `core_admin` | `script`, client-only | The admin panel and reports overlay, rendered as native MTA dxGUI/dxDraw (`client/gui/` - `AdminGuiWindow.lua`, `PlayersTab.lua`, `ReportsTab.lua`, `PenaltyDialog.lua`), not CEF. Has zero `server/` scripts - toggled by `/apanel`/`/reports` (`Events.ADMIN_PANEL_TOGGLE`/`REPORTS_OVERLAY_TOGGLE`, fired from `core`) and talks to the server over plain `triggerServerEvent`/`triggerClientEvent` pairs, not FetchBridge. Does NOT own the duty/report/penalty business logic itself - that lives in `core` (`AdminGuiEndpoints.lua` - see "Admin duty, panel, and reports" below) for the same reason `core_auth` doesn't own `AccountService`: anything that needs to call back into `core`'s services directly has to live in the same resource as those services. Includes only `core_shared`, not `core`/`core_ui`. |
| `system_notifications` *(empty placeholder today)* | — | Reserved for future systems that don't belong inside `core` but also don't have deep callback coupling with it. |
| `gm_roleplay` | `gamemode`, server-only | The actual gamemode entry point - deliberately thin. Has no knowledge of any UI (auth window or spawn-select window) - that's entirely `core_auth`'s job. Its responsibilities are `gameplayEnterWorld(player, location)` (exported, see `GameplayBootstrap.lua`): `spawnPlayer` + camera fade, called by `core_auth`'s `SpawnEndpoints.lua` once a player confirms a spawn choice; and local/IC chat (`Chat.lua` - see "Local chat" below). |

Start order: `core_shared` → `core` → `core_ui` → `core_loading` →
`core_auth` → `core_admin` → `gm_roleplay`, enforced automatically by `core_bootstrap`
rather than left to `mtaserver.conf`'s `<resource>` line order (which MTA
does not treat as a dependency graph) or manual `/start`/`/restart`
discipline - see `core_bootstrap/server/Bootstrap.lua`. `core_loading`
sits right before `core_auth` specifically so `core_auth`'s
`AuthUiController.lua` never starts listening for `Events.LOADING_READY`
before `core_loading` exists to fire it. The reasoning behind the order
itself: `core_ui` declares `<include resource="core">` (it needs
`PlayerService`/`SecurityService` early - `Logger` is the one exception:
`core_ui` has its own local copy, `core_ui/server/Logger.lua`, instead of proxying to
`core`'s. A proxied `Logger.debug` call that re-enters `core` via exports
while `core_ui` was itself entered FROM `core` - e.g.
`AccountEndpoints.lua`'s registration loop calling
`fetchBridgeRegisterMeta`, which called `Logger.debug`, which called back
into `core` - is a re-entrant cross-resource export call, and that
specific shape broke reliably in testing (`core_ui`'s own
`isResourceAvailable("core")` read `false` mid-reentrant-call even though
`core` was genuinely running). See `core_ui/server/Logger.lua`'s module
comment for the full account). `core` deliberately does **not** declare
`<include resource="core_ui">` even though `AccountEndpoints.lua` calls
into it - every cross-resource call in this project resolves lazily at
call time (see the `GlobalResources.lua` pattern above), so `core_ui`
only needs to be running by the time a browser request actually arrives,
not before `core` itself starts. A mutual `<include>` between the two
would work in practice (MTA's include is a soft start-order hint, not a
strict dependency gate) but is avoided since it's undocumented/unverified
behavior for the circular case.

`core_auth` declares `<include resource="core_ui">` (needs `uiOpen`/
`uiClose` for both the auth and spawn-select windows) but deliberately
does **not** declare `<include resource="gm_roleplay">`, even though
`SpawnEndpoints.lua` calls `exports.gm_roleplay:gameplayEnterWorld` - same
reasoning as the `core`/`core_ui` case above: the call resolves lazily at
the moment a player actually confirms a spawn choice, well after both
resources have started, and a core resource including a gameplay resource
would invert this project's core → systems → gameplay dependency
direction. `gm_roleplay` itself only declares `core_shared`/`core` - it
has no client-side scripts and no dependency on `core_ui`/`core_auth` at
all (see the resource responsibility table above).

Future systems (inventory, economy, jobs, organizations, ...) should
default to being their own resource under `systems/` or `gameplay/`,
talking to `core`/`core_ui` through exports/events - **only** merge a new
module into `core` if it needs to exchange closures with existing `core`
code constantly (the same reason `core`'s modules are merged together).

## Loading gate

A player connecting mid-boot (or on a slow client) could otherwise be
told to open the auth window before the server has actually finished
starting/checking its own resources, or before that player's own CEF
browser exists to render anything into. `core_loading` exists purely to
prevent that:

```
player connects
     |
     v
core_loading: LoadingGate.lua starts polling this player (every 200ms)
     |
     +-- exports.core_bootstrap:bootstrapIsChainReady()? ---- false --> keep polling
     |         (true once core_bootstrap's startNext has walked all the
     |          way through core_shared -> core -> core_ui -> core_loading
     |          -> core_auth -> gm_roleplay at least once)
     |
     +-- exports.core_ui:uiStateIsBrowserReady(player)? ----- false --> keep polling
     |         (true once THIS player's CEF frontend has fired
     |          Events.BROWSER_READY - see App.tsx's onMount -> mta.notify("ui.ready"))
     |
     v (both true)
core_loading: triggerEvent(Events.LOADING_READY, player)
     |
     v
core_auth: AuthUiController.lua's handler fires -> same
     "PlayerService.isAuthenticated(player)?" branch the account lifecycle
     diagram below describes, just gated on LOADING_READY instead of a
     raw onPlayerJoin
```

Polling (`LoadingGate.lua`, every `POLL_INTERVAL_MS`) rather than a
precise event chain - the two conditions can become true in either order,
or a player can already be connected when `core_loading`/`core_bootstrap`
itself restarts mid-session (handled by re-polling every currently
connected player on `core_loading`'s own `onResourceStart`) - covering
every interleaving with events would be more code for no real benefit
over a short poll. `LOADING_READY` fires at most once per player
connection (`readyFired`, cleared on `onPlayerQuit`).

On the CEF side, `App.tsx`'s `<Switch>` shows `ResourceCheckScreen`
(`packages/ui/src/features/loading/ResourceCheckScreen.tsx`) whenever
`uiStore.activeWindow()` is still `null` - not just while `authStore`'s
own `auth.status` round trip is pending (`phase() === "checking"`).
Without that `activeWindow() === null` check, a fast `auth.status`
response landing before `Events.LOADING_READY` (an entirely independent,
unrelated request - `auth.status` isn't gated by the loading gate at all)
would flip `phase()` to `"unauthenticated"` with no window open yet,
leaving a blank screen instead of a loading state until the auth window
push finally arrives. There is no separate native-dx loading screen
outside CEF - a player watches MTA's own resource download UI until
`core_ui`'s files finish downloading and the CEF frontend mounts, and
`ResourceCheckScreen` covers everything from that point until a window is
actually pushed.

Once mounted, `ResourceCheckScreen` isn't just a generic spinner: it also
shows this specific client's OWN resource-file download progress, driven
entirely client-side by `core_loading/client/DownloadTracker.lua` -
`onClientTransferBoxProgressChange`/`onClientTransferBoxVisibilityChange`
(MTA's native resource-download transfer box events, fired on `root`)
pushed straight into the CEF browser via `exports.core_ui:uiPushEvent`
("loading.progress") - never through the server, since a client's own
download progress is purely local to that client and has nothing to do
with `core_bootstrap`'s server-side chain state (which only tracks
whether resources have *started*, not what any given client has
*downloaded*). `core_loading` has the highest `download_priority_group`
of any project resource specifically so `DownloadTracker.lua` is running
before the bulk of the other resources' files start downloading to a
given client - MTA's own docs note a resource "cannot use
[`isTransferBoxActive`] to detect if its own files are downloaded", only
other resources' still-in-progress ones, so this ordering is what makes
the tracker useful at all. `loading.store.ts` mirrors the pushed payload
into `loadingStore.progress()`, which `ResourceCheckScreen` renders as a
byte-count progress bar - falling back to a plain spinner (`app.loading`)
until the first push arrives.

## Surviving a `core` restart while players are connected

`core/server/PlayerService.lua`'s `accountContexts` table - the runtime
cache behind `PlayerService.isAuthenticated`/`getAccount` - lives entirely
in `core`'s own Lua VM. Restarting `core` alone, or the whole chain via
`core_bootstrap`/`/restartchain` (e.g. after a code change), wipes it -
but every already-connected player stays connected the entire time (a
resource restart is not a disconnect). Without recovery, every
already-logged-in player would silently see the login screen again
despite never having left.

The fix persists just enough state as **element data** on the player
element itself, which - unlike a resource-local Lua table - survives that
resource restarting:
- `core_auth/server/AuthUiController.lua`'s `setupPlayerData` sets
  `player:logged = true` and `account:id`/etc. on the first successful
  login/register.
- `gm_roleplay/server/GameplayBootstrap.lua`'s `enterWorld` sets
  `player:spawned = true` once `spawnPlayer` actually runs.

`PlayerService.lua`'s own `onResourceStart` handler
(`reconnectAlreadyLoggedInPlayers`) reads this back for every currently
connected player and re-establishes `accountContexts` without making
anyone log in again:

```
core restarts (player stays connected the whole time)
     |
     v
PlayerService.lua's onResourceStart -> for each connected player:
     |
     +-- player:logged ~= true? ---------------------------> leave alone,
     |                                                        normal login
     |                                                        screen flow
     |
     +-- player:logged == true, player:spawned == true -----> AccountRepository.findById(account:id)
     |         (already standing in the world)                     |
     |                                                              v
     |                                          PlayerService.restoreAccountContextSilently
     |                                          (no PLAYER_ACCOUNT_RESOLVED - does NOT
     |                                           re-open spawn-select or re-run enterWorld)
     |
     +-- player:logged == true, player:spawned ~= true -----> AccountService.resolveForPlayer
               (was mid auth/spawn-select)                          |
                                                                     v
                                                     fires PLAYER_ACCOUNT_RESOLVED normally -
                                                     core_auth/gm_roleplay drive them through
                                                     spawn-select same as any fresh login
```

**A gap in the diagram above**: when the WHOLE chain restarts
(`core_bootstrap`/`/restartchain`), `core` (2nd in `START_ORDER`) runs its
`onResourceStart`-driven reconnect *before* `core_auth` (5th) has even
started again - so `PLAYER_ACCOUNT_RESOLVED`, fired for an
already-logged-in-but-not-yet-spawned player in the last branch above,
has no listener yet and is silently lost. `accountContexts` still gets
correctly rebuilt (that part happens entirely inside `core`, independent
of `core_auth` being up), but the client is never told to reopen the
spawn-select window this way.

`core_auth/server/AuthUiController.lua` closes this gap with its own
`onResourceStart` handler (`reopenSpawnSelectForUnspawnedPlayers`), which
doesn't depend on that event arriving at all - it re-derives the same
"logged in, not yet spawned" condition independently
(`PlayerService.isAuthenticated(player)` + the same `player:spawned`
element data `core`'s reconnect logic already reads) and re-sends
`Events.SPAWN_SELECT_OPEN` directly. This runs correctly regardless of
*why* `core_auth` just started - whether it restarted alone (`core`'s
`accountContexts` never needed rebuilding in the first place) or as part
of a full chain restart (`accountContexts` was already silently rebuilt
by the time this handler runs, whether or not `PLAYER_ACCOUNT_RESOLVED`
made it to a listener).

Any future resource-local runtime cache with the same "must survive this
resource's own restart, but not a real disconnect" requirement should
follow the same element-data pattern (see gotcha #12 in `AGENTS.md`)
rather than inventing a different persistence mechanism - and if a
downstream resource reacts to an event fired during that recovery (the
way `core_auth` reacts to `PLAYER_ACCOUNT_RESOLVED`), remember that a
full-chain restart can start resources in an order where the event's
firer runs before its listener even exists, exactly as above.

## Account lifecycle

```
player connects
     |
     v
core_loading: LoadingGate.lua polls until bootstrapIsChainReady() AND
     uiStateIsBrowserReady(player) are both true (see "Loading gate" above),
     then triggerEvent(Events.LOADING_READY, player)
     |
     v
core_auth: AuthUiController.lua's Events.LOADING_READY handler fires ->
     PlayerService.isAuthenticated(player)?
     +-- yes --> triggerClientEvent Events.SPAWN_SELECT_OPEN ("spawn:selectOpen")
     |                 -> client: AuthUiClient.lua -> UI.open("spawnSelect")
     |                 (reconnecting mid-session skips the auth window entirely,
     |                  but still has to pick a spawn - see "spawn.select" below
     |                  for what happens once they do)
     |
     +-- no --> triggerClientEvent Events.AUTH_BEGIN_AUTHENTICATION ("auth:beginAuthentication")
                      |
                      v
                client: core_auth/client/AuthUiClient.lua -> UI.open("authentication")   (core_ui)
                      |
                      v
                CEF loads, SolidJS mounts, calls mta.notify("ui.ready")
                      |
                      v
                player submits login + email + password (register) or
                      login/email + password (login) in the auth form
                      |
                      v
                CEF: authApi.register({ login, email, password }) or
                      authApi.login({ login, password })
                      -> mta.fetch("auth.register" | "auth.login", [...])
                      |
                      v
                client Lua Transport.lua (core_ui) forwards to server FetchBridge
                      |
                      v
                core_ui: FetchBridge validates envelope, rate limit, fires
                      triggerEvent("endpoint:auth.register" | "endpoint:auth.login",
                                   ..., requestId, player, payload)
                      |
                      v
                core: AccountEndpoints.lua's addEventHandler picks it up
                      |
                      v
                AccountService.register -> validates input, checks uniqueness,
                      passwordHash(password, "bcrypt", {cost=10}, cb) (async, native MTA bcrypt),
                      AccountRepository.create
                  (or)
                AccountService.login -> looks up by login/email,
                      passwordVerify(password, account.password_hash, {}, cb),
                      rebinds mta_serial to the current client on success
                      |
                      v
                AccountService.resolveForPlayer -> PlayerService.setAccountContext
                      |
                      +--> fires Events.PLAYER_ACCOUNT_RESOLVED (plain custom event -
                      |         engine-global, both handlers below live in core_auth but
                      |         fire independently and don't know about each other)
                      |         |
                      |         +--> core_auth: SpawnUiController.lua's handler
                      |         |         fires, triggerClientEvent Events.SPAWN_SELECT_OPEN
                      |         |         ("spawn:selectOpen") -> client: SpawnUiClient.lua
                      |         |         -> UI.open("spawnSelect") (player is NOT spawned yet)
                      |         |
                      |         +--> core_auth: AuthUiController.lua's handler fires,
                      |                   triggerClientEvent Events.AUTH_SUCCESS_AUTHENTICATION
                      |                   ("auth:successAuthentication") -> client:
                      |                   AuthUiClient.lua -> UI.close("authentication")
                      |
                      +--> exports.core_ui:fetchBridgeRespond(requestId, {success=true, data=...})
                                |
                                v
                          core_ui: FetchBridge looks up the pending request,
                                triggerClientEvent sends the response to the browser
                                |
                                v
                          CEF: auth.store.ts updates, LoginView unmounts
                                (the auth:successAuthentication-triggered UI.close above is
                                 what actually hides the auth window - this is just the
                                 store update; SpawnSelectView then mounts, see below)
                                |
                                v
                          CEF: SpawnSelectView calls spawnApi.list() -> spawn.list,
                                player picks a card -> spawnApi.select(id) -> spawn.select
                                |
                                v
                          core_auth: SpawnEndpoints.lua's spawn.select handler validates
                                the id against SpawnLocations.lua, calls
                                exports.gm_roleplay:gameplayEnterWorld(player, location)
                                |
                                v
                          gm_roleplay: GameplayBootstrap.lua's gameplayEnterWorld ->
                                spawnPlayer + fadeCamera (its only responsibility - see
                                the resource responsibility table above)
                                |
                                v
                          core_auth: back in the same spawn.select handler, triggerClientEvent
                                Events.SPAWN_SELECT_CLOSE ("spawn:selectClose") -> client:
                                AuthUiClient.lua doesn't close the window immediately - it
                                waits for onClientPlayerSpawn to actually fire for localPlayer
                                first, so the player sees a loading state through the spawn
                                itself instead of a jarring cut into an unfinished world.
```

Authentication is a real login/email + bcrypt-hashed password pair (MTA's
native `passwordHash`/`passwordVerify`, `"$2y$"` format - see
`DatabaseContract.md`'s "Accounts table" section). `mta_serial` (MTA's own
`getPlayerSerial(player)`) is stored per account purely as a "recognize a
returning client" convenience, rebound on every successful login - it is
**not** the authentication credential and is never sufficient on its own
to establish identity, since MTA serials are not cryptographically
unforgeable. Account primary keys are MySQL `AUTO_INCREMENT` integers, not
UUIDs - see `Uuid.lua`/`Schema.lua`'s `"uuid"` column type, which remains
available for future columns that genuinely want an app-generated,
non-sequential identifier (e.g. a public share id), just not as an
account/character primary key.

## Premium accounts

`accounts.premium_expires_at` (nullable `TIMESTAMP`) is the single source
of truth for premium status - there is no separate boolean column. NULL or
a past timestamp means "not premium"; a future timestamp means "premium
until then" (`AccountService.isPremiumActive`/`toPublic` - the latter is
what the public DTO sent to CEF exposes as `isPremium`/`premiumExpiresAt`).

Three places touch it, each for a different moment in a player's session:

- **Login/register/reconnect** - `AccountService.resolveForPlayer` clears
  a lapsed `premium_expires_at` back to NULL (via `AccountRepository.
  clearExpiredPremium`, which goes through `Account:query():update({
  premium_expires_at = Model.NULL })` - see "Database abstraction and the
  ORM" below for `Model.NULL`) so an expired period doesn't sit in the
  column looking like still-active data.
- **Establishing the session** - `PlayerService.setAccountContext` (fired
  for every fresh login/register, and for a resource-restart reconnect
  that resolves through the normal `AccountService.resolveForPlayer`
  path - see "Surviving a `core` restart" above) shows a chat message
  with the formatted expiry (`AccountService.formatExpiryForDisplay`) and
  mirrors the flag onto `account:premium` element data, the same pattern
  `player:logged`/`account:*` already use, so any resource can check
  premium status cheaply without a `PlayerService.getAccount` round trip.
- **Mid-session expiry** - the two points above only ever clear/announce
  premium at login time, so a player whose premium lapses *while already
  connected* wouldn't otherwise be caught until their next login.
  `PlayerService.lua` runs a self-rescheduling `setTimer` sweep every 5
  minutes (`schedulePremiumSweep`/`sweepExpiredPremium`, started on this
  resource's own `onResourceStart`) that re-checks every logged-in
  player's account row in the database, and for anyone whose
  `account:premium` element data is set but whose premium has actually
  lapsed: calls `removeElementData(player, "account:premium")`, clears
  the stale expiry from the in-memory `accountContexts` cache, persists
  the NULL via `AccountRepository.clearExpiredPremium`, and fires
  `Events.PLAYER_PREMIUM_EXPIRED` (a plain custom event, engine-global
  like `PLAYER_ACCOUNT_RESOLVED`/`_CLEARED`). Any future system granting
  premium perks (VIP skins, items, etc.) should listen for both
  `PLAYER_ACCOUNT_RESOLVED` (grant, if `account:premium` is set) and
  `PLAYER_PREMIUM_EXPIRED` (revoke) rather than polling the flag itself.
  The sweep re-schedules itself at the end of its own timer callback
  instead of using `setTimer`'s infinite-repeat count, so a slow sweep
  can never stack overlapping runs.

## Account penalties (ban/mute/warn/kick)

`account_penalties` is a separate table (`core/server/database/models/
AccountPenalty.lua`) from `accounts` - one row per penalty ever issued,
never deleted (a full audit trail, not a mutable "current status" on the
account row itself). `type` is a SQL `ENUM` (`Schema.lua`'s `"enum"`
column type, added for this) whose values come from `Enums.PenaltyType`
(`BAN`/`MUTE`/`WARN`/`KICK`) - the one enum in this project backed by a
real SQL `ENUM` rather than a `VARCHAR`, a deliberate choice over the
`premium_expires_at`-style "just a string, validated in Lua" approach:
the tradeoff is that adding a new penalty type later needs a manual
`ALTER TABLE ... MODIFY COLUMN` (`Schema.migrate()` never alters an
existing column), not just a `Enums.lua` edit.

- **BAN/MUTE** carry `expires_at` (nullable - NULL means permanent, a
  future timestamp means active until then, same NULL/past/future shape
  as `premium_expires_at`).
- **WARN/KICK** are pure log entries - `expires_at` is always NULL for
  these regardless of what's passed in, they carry no duration concept.
- **`revoked_at`** (nullable) is set when an admin lifts a penalty early
  (`AccountPenaltyService.revoke`) - kept distinct from `expires_at`
  passing naturally so the audit trail can tell "ran its course" apart
  from "an admin reversed this".
- **`mta_serial`** (nullable) optionally ties a BAN to the offending
  player's MTA hardware serial in addition to `account_id`, so a ban can
  still block re-entry via a fresh account created on the same machine -
  not yet checked anywhere (only `account_id` is enforced today, see
  below), reserved for a future serial-based check.
- **`issued_by_account_id`** is BIGINT-typed (`Schema.lua`'s `"reference"`
  column type, for the same MySQL exact-type-match reason as
  `Character.account_id`) but deliberately has NO `references` entry, so
  no FOREIGN KEY constraint is created - an admin's own account being
  deleted later must never cascade into or block deletion of penalty
  history rows they issued against other accounts.

`AccountPenaltyService.lua` is the only thing that talks to
`AccountPenaltyRepository` - `ban`/`mute`/`warn`/`kick` each take a
`durationSeconds` (number, converted to an absolute `expires_at` once at
issue time) or `nil` for permanent, plus an optional `reason`/
`issuedByAccountId`. `isBanned(accountId, onResult, onError)` is the
enforcement check: `AccountService.login` calls it right after
`passwordVerify` succeeds (deliberately AFTER, not before, password
verification - a banned account's status is never revealed to someone
who doesn't already know the password, same reasoning as
`INVALID_CREDENTIALS` itself) and rejects the login with
`ErrorCodes.ACCOUNT_BANNED` if there's an active ban. MUTE has no
enforcement point yet - no chat system lives in `core` (see "Why the
split" above) - a future chat system would call
`AccountPenaltyService.isMuted` the same way.

`QueryBuilder.lua`'s `:where` gained `Model.NULL` support
(`:where("revoked_at", "IS", Model.NULL)`) alongside the `Model.NULL`
support `:insert`/`:update` already had (see "Database abstraction and
the ORM" below) - `findActiveBans` needs `revoked_at IS NULL`, and `= ?`
can never match SQL NULL no matter what's bound, so this needed its own
`IS [NOT] NULL` code path rather than reusing the `= ?`/`NULL`-literal
trick insert/update use.

**Issuing a penalty today**: `core/server/commands/
AccountPenaltyCommands.lua` - `/ban`, `/unban`, `/mute`, `/warn`, `/kick`
server console or F8 admin chat commands. Target resolution
(`CommandRegistry.resolveTargetAccount` - shared by every command that
targets a player/account, not just these, see `AccountRoleCommands.lua`'s
`/setrole` below too) tries `PlayerId.tryResolve` first - a runtime
player id or a fragment of a connected player's name (see "Player
lookup" below) - then falls back to a real login lookup
(`AccountRepository.findByLogin`), so e.g. `/ban 5 7d griefing`, `/ban
someone 7d griefing` (name fragment), and `/ban someuser 7d griefing`
(exact login, works even if `someuser` is offline) are all valid.
Permission goes through `CommandRegistry.register` (see "Account roles
and permissions" below for the actual check) - `/ban` requires
`Permissions.Bit.BAN`, `/mute` requires `MUTE`, `/warn` requires `WARN`,
`/kick` requires `KICK`, `/unban` requires `REVOKE_PENALTY`. Issuing a
`/ban` or `/kick` against a currently-connected player also ends their
session immediately via `kickPlayer` (a ban alone only blocks *future*
logins - see `AccountService.login` above - it does not end an
already-established one on its own). Warn/mute/kick/ban can also be
issued from the dxGUI admin panel's Players tab (see "Admin duty, panel,
and reports" below) - both paths funnel through the same
`AccountPenaltyService` calls, so behavior is identical either way.

## Player lookup (runtime id / name fragment)

`core/server/PlayerId.lua` assigns every connected player a short,
stable numeric id (lowest-first-free, e.g. 1, 2, 3 - freed back on
`onPlayerQuit`, not required to stay gap-free) purely for the duration of
their connection - unrelated to and independent from any account/login
identity, and does not survive a `core` restart (every already-connected
player is simply re-assigned a (possibly different) id on
`onResourceStart`, since nothing persists one past a single session).
Stored as `player:id` element data, same pattern as `player:logged`/
`account:premium`.

`PlayerId.tryResolve(target)` accepts either a numeric id or a
case-insensitive substring of a connected player's name (MTA color codes
stripped first, so a color-coded nickname still matches on its visible
text) and returns `(match, ambiguous)` - silent, no side effects, used
when a caller wants to try this before falling back to something else
(see `CommandRegistry.resolveTargetAccount` above).
`PlayerId.resolve(player, target)` is the same lookup but sends `player`
an error notification (`NotificationService`) and returns `nil` on
failure - the standalone entry point for a caller with no fallback of its
own. Both are exported (`playerIdById`/`playerIdOf`/`playerIdResolve`) as
flat functions for other resources.

## Account roles and permissions

`accounts.role` (plain `INT`, default `0`) stores one of `Enums.
AccountRole`'s static indices (`core_shared/shared/Enums.lua`) -
`PLAYER`(0) < `VETERAN`(1) < `SUPPORTER`(2) < `MODERATOR`(3) <
`ADMINISTRATOR`(4) < `RCON`(5) < `BOARD`(6, "Zarząd"). The enum is just
the ordered role list - it grants nothing by itself.

`core/server/accounts/Permissions.lua` maps each role to a permission
**bitmask** (`Permissions.Bit.WARN/MUTE/KICK/BAN/VIEW_PENALTY_HISTORY/
REVOKE_PENALTY/SET_ROLE`, each a distinct power of two) rather than doing
`role >= MODERATOR`-style comparisons at every call site - this is a
lookup table (`ROLE_PERMISSIONS`), not an inheritance mechanism, so a
future role reshuffle (e.g. splitting MODERATOR into two tiers with
different powers) only edits that one table. Built additively -
`MODERATOR` gets `WARN+MUTE+KICK+VIEW_PENALTY_HISTORY`, `ADMINISTRATOR`
adds `BAN+REVOKE_PENALTY` on top, `RCON`/`BOARD` add `SET_ROLE` on top of
that; `PLAYER`/`VETERAN`/`SUPPORTER` currently grant nothing.
`Permissions.has(account, Permissions.Bit.BAN)` tests a bit via plain
arithmetic (`math.floor(mask / bit) % 2 == 1`) since Lua 5.1/MTA has no
native bitwise operators - safe here because every mask is built from
distinct, non-overlapping bits.

**This is the sole authorization mechanism for admin commands** -
`core/server/commands/CommandRegistry.lua`'s `CommandRegistry.register(name,
permissionBit, handler)` is the only way any command in this project is
registered, and it checks exclusively `Permissions.has(PlayerService.
getAccount(player), permissionBit)`. There is no MTA ACL
(`hasObjectPermissionTo`/`acl.xml`) involved anywhere in this path - a
connected-but-not-yet-logged-in player has no account and therefore no
permissions, same as anyone else lacking the bit; the command silently
does nothing. The server's own console (`player` is `nil`/`false`, MTA's
convention for a console-issued command) always bypasses the check
entirely, same as before.

`AccountService.setRole(accountId, role, callback)` validates `role`
against `Enums.AccountRole` before writing it (`AccountRepository.
updateRole`). The only way to change a role today is `core/server/
commands/AccountRoleCommands.lua`'s `/setrole <login> <role>` command
(e.g. `/setrole someuser moderator`), which requires
`Permissions.Bit.SET_ROLE` - only `RCON`/`BOARD` have it, so only they can
grant roles (including granting `RCON`/`BOARD` itself - there is no
extra restriction beyond the bit check).
`AccountService.toPublic` includes `role` in the DTO sent to CEF (default
`Enums.AccountRole.PLAYER` if unset) - the frontend mirrors the enum as
`AccountRole` in `packages/ui/src/types/account.ts`.

## Local chat

`gm_roleplay/server/Chat.lua` fully replaces MTA's default
`onPlayerChat` broadcast - `cancelEvent()` unconditionally, then a
hand-formatted, range-limited `outputChatBox` instead. Lives in
`gm_roleplay`, not `core` - chat is gameplay-facing behavior, not
account/database infrastructure. Reaches the narrow slice of `core` it
needs (`PlayerService.getRole`, `PlayerId`, `Permissions.colorForRole`,
`AccountService.formatExpiryForDisplay`, `NotificationService`) through
the same lazy-metatable proxy pattern `core`'s own `GlobalResources.lua`
uses for `core_shared`/`core_ui` (see `gm_roleplay/server/
GlobalResources.lua`) - notably `PlayerService.getRole(player)` returns
only a role number, never the full account record
(`PlayerService.getAccount`), which deliberately never crosses `core`'s
exports boundary. Format:

```
1 Norelock: fajna wiadomość
```

`1` is the sender's `player:id` element data (the runtime id `core`'s
`PlayerId.lua` assigns - see "Player lookup" above) in a fixed gray; the nickname is colored per
`colorForPlayer`; the message body is plain white. Both the nickname
(MTA lets a player set their own embedded `"#RRGGBB"` color codes in
their name) and the message text are run through `escapeColorCodes`
first (`"#RRGGBB"` → `"# RRGGBB"`) so neither can inject a color switch
into `outputChatBox`'s `colorCoded=true` line or coincidentally contain a
literal `#` followed by 6 hex digits.

**Color precedence**: a fixed per-role color
(`Permissions.colorForRole` - `MODERATOR`/`ADMINISTRATOR`/`RCON`/`BOARD`
each have one, see `Permissions.lua`'s `ROLE_COLORS`) always wins over
premium; premium (`#e3b017` gold, `AccountService.isPremiumActive`) wins
over the default white for `PLAYER`/`VETERAN`/`SUPPORTER` - those three
roles have no fixed color of their own today.

**Range**: local/IC chat, not a server-wide broadcast - only players
within `CHAT_RANGE` (30 units, full 3D distance via
`getDistanceBetweenPoints3D`, so a different floor of the same building
is out of range even at small XY distance) AND in the same dimension AND
the same interior as the sender receive the message. Two players at
identical world coordinates but different interiors/dimensions never
hear each other regardless of distance - same isolation MTA already
gives those two concepts everywhere else (visibility, damage, ...).

**Mute enforcement**: a muted account's message is swallowed entirely (no
`outputChatBox` to anyone, just a one-time `NotificationService` error to
the sender showing the reason/expiry) - checked via `account:mute`
element data, never a direct `AccountPenaltyService.isMuted` call from
inside the handler, since a chat message needs a synchronous yes/no and
`isMuted` is an async database round trip. Unlike `account:premium`
(a plain boolean), `account:mute` holds a **table** of the active mute
row's plain-data fields (`id`/`reason`/`expiresAt`/`createdAt` - see
`PlayerService.lua`'s `toMuteElementData`, which deliberately excludes
internal/audit-only columns like `mta_serial`/`issued_by_account_id`) and
is removed entirely (not set to `false`) once there's no active mute, so
`getElementData(player, "account:mute") ~= nil` alone is the presence
check - this lets the rejection notice say *why* and *until when*
without its own database round trip. `PlayerService.lua`'s
`scheduleMuteSweep` (every 30s, far more often than
`schedulePremiumSweep`'s 5min - a mute taking minutes to take effect
would be a poor admin experience) keeps it current, in both directions:
unlike premium (which today can only be granted before a session
starts), a `/mute` can land on an already-connected player mid-session,
so the sweep both sets `account:mute` for a freshly-muted player and
clears it once the mute expires or is revoked (and refreshes the payload
every pass even while already muted, in case a revoke+re-mute happened
between sweeps). `PlayerService.setAccountContext` also checks once at
login/reconnect, so the flag is already correct the moment a session
starts rather than waiting for the sweep's first pass.

A player who hasn't finished login (`player:logged`) or hasn't picked a
spawn yet (`player:spawned`) cannot send a chat message at all - checked
directly via those two element data flags before anything else runs.

## Admin duty, panel, and reports

`Permissions.Bit` values backing this whole feature: `ADMIN_PANEL`,
`TOGGLE_DUTY`, `VIEW_REPORTS`, `RESOLVE_REPORTS` - granted starting at
`MODERATOR` (see `Permissions.lua`'s `MODERATOR_PERMISSIONS`), same tier
as the existing penalty bits - plus `VIEW_STATS`, granted only to
`RCON`/`BOARD` (see "Admin duty statistics" below).

**Duty** (`PlayerService.setDuty`/`isOnDuty`, `core/server/PlayerService.lua`)
is a purely runtime, per-connection flag - like `PlayerId`'s runtime ids,
and unlike `account:premium`/`account:mute`, the RUNTIME flag itself
doesn't persist across a `core` restart: duty means "I'm actively
working right now", so losing the live flag on a restart (going back
off-duty) is correct, not a bug (the historical record of HOW LONG
someone was on duty is persisted separately - see "Admin duty
statistics" below). Toggled via `/duty`
(`core/server/commands/AdminCommands.lua`, requires `TOGGLE_DUTY`,
always self-targeted).

`player:admin` element data holds a **table**, not a bare boolean, while
on duty (absent entirely while off duty - `~= nil` is the presence
check, same convention `account:mute` uses): `{ role, dutySince }` -
`role` is the account's `Enums.AccountRole` snapshotted at the moment
duty turned on, `dutySince` is `os.time()` at that moment. Deliberately
a timestamp, not a running "seconds on duty so far" counter - nothing
has to rewrite element data every second just to keep a duration
current; any reader computes `os.time() - dutySince` itself, on demand.
`gm_roleplay/server/Chat.lua` reads this (presence only) to decide
whether an on-duty admin's chat nickname gets Permissions.colorForRole's
fixed color instead of the normal premium/default color - an off-duty
admin chats with no special color at all, same as anyone else. There is
no chat-line duty prefix (removed - considered noise).

`core_admin/client/gui/KeyBinds.lua` binds F6 (`/apanel`)/F7 (`/reports`)
only while the LOCAL player is on duty, unbinding both the moment duty
turns off - driven by `Events.ADMIN_DUTY_CHANGED` (server push,
self-targeted, fired by `/duty`) and `Events.ADMIN_REQUEST_DUTY_STATUS`
(client asks once on its own start, to learn the current state if
`core_admin` started/restarted after duty was already toggled on). An
admin who never ran `/duty` gets no shortcut at all; `/apanel`/`/reports`
typed directly in F8 chat still work regardless of duty status - the
keybinds are a convenience layered on top, not a new permission gate.

**Reports** (`Report.lua`/`ReportRepository.lua`/`ReportService.lua`,
all in `core`, mirroring `AccountPenalty`'s three-layer shape exactly)
are filed via `/report <target> <reason>` (any logged-in player, no
permission bit - `core/server/commands/AdminCommands.lua`) or the admin
panel's Reports tab. A report row is never deleted, only marked
`status = "resolved"` plus `resolved_at`/`resolved_by_account_id` (same
"historical audit trail" convention `account_penalties` uses).
`reporter_account_id`/`reported_account_id` both get real FOREIGN KEY
constraints (ordinary player accounts, no "might get deleted" concern),
but `resolved_by_account_id` deliberately does NOT - same audit-only,
no-cascade shape as `account_penalties.issued_by_account_id`.
`Events.REPORT_CREATED` (a plain custom event, fired by
`ReportService.create`) is relayed by `core/server/accounts/
AdminGuiEndpoints.lua` (in `core`, not `core_admin` - see below) to
every currently on-duty admin via `triggerClientEvent`
(`Events.ADMIN_REPORT_CREATED_NOTICE`) - not to admins who merely have
the permission but aren't on duty - so the panel/overlay can refresh and
show a chat notice immediately instead of only being noticed the next
time someone opens it.

**The admin panel is native MTA dxGUI/dxDraw, not CEF**
(`core_admin/client/gui/`) - the project owner supplied a working
reference implementation of a dxGUI admin panel from a prior project,
and asked for this panel to follow that shape rather than being built in
the SolidJS/CEF frontend. Because there is no CEF browser involved, none
of `core_ui`'s FetchBridge/PushService/`BrowserManager` machinery
applies here at all - the panel talks to the server over plain
`triggerServerEvent`/`triggerClientEvent` request/response pairs instead
(`Events.ADMIN_REQUEST_PLAYER_LIST`/`ADMIN_PLAYER_LIST`/
`ADMIN_REQUEST_REPORT_LIST`/`ADMIN_REPORT_LIST`/`ADMIN_RESOLVE_REPORT`/
`ADMIN_ISSUE_PENALTY`), conceptually the same request/response shape as
FetchBridge, just a different transport with no browser in the middle.

`core_admin/client/gui/` splits the panel per concern rather than one
monolithic file: `AdminGuiWindow.lua` owns the shared `window`/`tabPanel`
handles, the `ADMIN_PANEL_TOGGLE` open/close logic, and an
open/close-callback registration hook (`AdminGuiWindow_onPanelOpen`/
`_onPanelClose`) so each tab can hook into panel visibility without
`AdminGuiWindow.lua` needing to know the tabs exist; `PlayersTab.lua`
(the "Gracze" tab - grid of online players + warn/mute/kick/ban buttons);
`ReportsTab.lua` (the "Zgłoszenia" tab's grid/resolve button, **plus**
the small always-available dxDraw reports overlay HUD toggled
independently by `/reports`/`Events.REPORTS_OVERLAY_TOGGLE` - grouped
together since both render the same `reportsList` and both need to react
to `ADMIN_REPORT_CREATED_NOTICE`); `PenaltyDialog.lua` (one shared
confirmation window reused for all four penalty types, opened by
`PlayersTab.lua`'s buttons). All four are plain globals loaded in
sequence via `meta.xml` (same convention as every other resource here -
no module/require system), with `AdminGuiWindow.lua` loaded first since
the tab files reference `window`/`tabPanel` once `onClientResourceStart`
fires.

`/apanel` (`core/server/commands/AdminCommands.lua`, requires
`ADMIN_PANEL`) toggles the panel by firing `Events.ADMIN_PANEL_TOGGLE` -
checked server-side before that event is even sent, so the panel is
never told to open for someone without the permission. `/reports`
(requires `VIEW_REPORTS`) independently toggles just the dxDraw overlay
via `Events.REPORTS_OVERLAY_TOGGLE`, so an admin can glance at open
reports without the full panel open.

**Every request handler in `core/server/accounts/AdminGuiEndpoints.lua`
re-checks `Permissions.has` itself** - a client asking for panel data,
or to perform an action, is never proof it's allowed to (same
"never trust the client" rule `docs/UiBridge.md` states for the
CEF/FetchBridge leg, applying identically here even though there's no
browser involved). A failing check is simply ignored (no response sent)
rather than told why - unlike FetchBridge's `ErrorCodes.FORBIDDEN`
response, there's no user-facing error surface to report to here, since
the dxGUI panel doesn't show its own controls at all unless the local
player's account already grants the relevant bit. Penalty issuance
(warn/mute/kick/ban) is funneled through one `Events.ADMIN_ISSUE_PENALTY`
handler that reuses `AccountPenaltyService` exactly like the F8 commands
do - see `AdminGuiEndpoints.lua`'s `PENALTY_TYPE_PERMISSION`/
`PENALTY_ISSUER` tables, which keep each penalty type's required bit
from ever drifting out of sync with the service call it authorizes.

**`AdminGuiEndpoints.lua` lives in `core`, not `core_admin`** - same
reason `AccountEndpoints.lua` does: a Lua closure can't cross a resource
boundary, so anything that needs to call back into `ReportService`/
`AccountPenaltyService`/`PlayerService` directly has to live in the same
resource those services do. `core_admin` itself is client-only (no
`server/` scripts at all) and owns nothing but dxGUI/dxDraw rendering -
it includes only `core_shared` (for `Events`/`Enums`, via its own
`GlobalResources.lua`, the same lazy-metatable pattern every other
resource uses) and never calls into `core`/`core_ui` directly; all
communication with `core` happens over the plain events above.

### Admin duty statistics

`AdminDutySession.lua`/`AdminDutySessionRepository.lua` (table
`admin_duty_sessions` - deliberately NOT named `duty_sessions`, to avoid
colliding with a future non-admin duty/group/faction system) record one
row per continuous stretch of time an admin held duty: `account_id`,
`started_at`, `ended_at` (nullable - NULL means still open, either
currently on duty or left open by an unclean stop, see below). Never
deleted, only completed, same "historical audit trail" convention
`account_penalties`/`reports` use.

`AdminDutyStatsService.lua` (`core/server/accounts/`) owns this domain:
`startSession`/`finishSession` (called by `/duty`'s handler alongside
`PlayerService.setDuty` - the RUNTIME flag and the PERSISTED session are
distinct things toggled together by the same command),
`statsForAccount`/`statsForEveryAdmin` (total duty time, session count,
penalties issued, reports resolved - the latter two counted via new
`AccountPenaltyRepository.countIssuedByAccountId`/
`ReportRepository.countResolvedByAccountId` methods against
`issued_by_account_id`/`resolved_by_account_id`, no new tables needed
for those). Total duty time is summed in Lua after one
`findByAccountId` query (an open session counts up to "now") rather
than a SQL `SUM`/`TIMESTAMPDIFF` - keeps this project's "every
repository goes through QueryBuilder, no raw aggregate SQL" convention
intact for what's a single, low-volume caller.

`statsForEveryAdmin` returns every account that has EVER held a duty
session, not merely every account with `MODERATOR+` role today - a
demoted former admin's historical stats stay visible (role changes never
delete `admin_duty_sessions`/`account_penalties` rows).

**Orphaned open sessions**: if `core` stops uncleanly (crash, `restart
core`, console `killResource`) while an admin is on duty, that session's
`ended_at` would stay NULL forever with nothing to close it -
`closeOrphanedSessions` runs once `Events.DATABASE_READY` fires (NOT
`onResourceStart` - see `DatabaseContract.md`'s "Migration" section for
why querying a fresh table that early is unsafe; this exact bug was
caught live for `admin_duty_sessions`) and closes every still-open
session as of THAT moment (not as of whenever the actual crash happened,
since that instant isn't recorded anywhere).
This slightly overcounts total duty time for whatever session was open
at the moment of an unclean stop - an accepted, bounded inaccuracy for a
stats feature never used for anything security/authorization-relevant,
versus the alternative of an ever-growing set of permanently-open
sessions inflating "time on duty" for as long as the server keeps
running afterward.

**Access is `VIEW_STATS`-gated, RCON+/BOARD ONLY** - deliberately not
folded into `ADMINISTRATOR_PERMISSIONS` the way every other bit in this
feature is (see `Permissions.lua`'s own comment on why): per-admin
activity numbers are for top-level oversight of the admin team itself,
not something every Administrator should be able to pull up on peers at
their own rank. `core/server/accounts/AdminGuiEndpoints.lua`'s
`ADMIN_REQUEST_STATS` handler checks `VIEW_STATS` specifically (not
`ADMIN_PANEL`, unlike the other tabs' handlers). The dxGUI panel goes
one step further than the usual "server is the only real boundary,
client-side hiding is cosmetic" stance: `AdminGuiEndpoints.lua` also
pushes `Events.ADMIN_PERMISSIONS` (`{ viewStats: boolean }`,
self-targeted) once per panel open, piggybacked on the
`ADMIN_REQUEST_PLAYER_LIST` response (since that fires exactly once per
open) - `core_admin/client/gui/StatsTab.lua` only builds/shows the
"Statystyki" tab at all when `viewStats` is true, so an Administrator
never even sees the tab exists rather than seeing one that silently does
nothing when clicked. The actual authorization boundary is still
entirely server-side, same as everywhere else in this file - this push
is a presentation-layer courtesy on top of it, not a substitute for it.

## "Remember me" (local credential persistence)

`core_auth`'s client-side half lets the login form pre-fill itself on
the next launch, so a player doesn't retype their login and password every
time. This is **entirely local to the player's machine** - it never
touches the server, never goes through FetchBridge, and has no bearing on
real authentication: the (pre-filled) form is still submitted normally and
the server still runs `passwordVerify` exactly as if the player had typed
it fresh.

```
CEF: "remember me" checked + successful login
     |
     v
mta.saveCredentials(login, password)   (lib/mta/MtaBridge.ts)
     |
     v
window.mta.triggerEvent("credentials.save", obfuscatedPayload)
     |
     v
core_ui/client/ui/Transport.lua - verifies source is the tracked browser
     element, then triggerEvent("credentials.save", root, obfuscatedPayload)
     |
     v
core_auth/client/CredentialTransport.lua - deobfuscates (via
     exports.core_ui:uiDeobfuscateFromBrowser), calls CredentialStore.save
     |
     v
core_auth/client/CredentialStore.lua - xmlCreateFile("@credentials.xml", ...),
     obfuscated with a FIXED local key (not the per-session key), xmlSaveFile
```

Loading mirrors this in reverse: `mta.loadCredentials()` resolves a
`SavedCredentials | null` once `window.__mtaCredentialsLoaded` is called
(or times out after 3s) - see `MtaTransport.ts`.

Two independent obfuscation layers are involved, with two different keys,
for two different reasons:

- The CEF↔Lua leg (`credentials.save`/`credentials.load`'s wire payload)
  uses the same per-session key as every other browser↔Lua message (see
  `docs/UiBridge.md`'s "Payload obfuscation" section) - this key doesn't
  survive a restart, which is fine, since this leg only exists transiently
  while the message is in flight.
- The **on-disk** XML file (`CredentialStore.lua`) uses a separate, FIXED
  local key baked into the client script, because the whole point is
  surviving a full client restart with no server round trip - a
  per-session key literally cannot be used here. This is explicitly
  weaker than the session-key scheme: the fixed key is the same for every
  install, so anyone who can read the shipped client script recovers it.
  Combined with `"@credentials.xml"`'s per-connected-server-private
  storage (see `Filepath` on the MTA wiki), this raises the bar above "a
  plaintext file anyone with basic file access on THIS machine can open
  in Notepad" - it is not a real secret, and is not meant to withstand a
  motivated attacker with access to the player's own machine. See
  `CredentialStore.lua`'s own module comment for the full, deliberately
  blunt statement of this tradeoff.

`core_auth` is a separate resource from `core_ui` specifically so
auth-specific code doesn't accumulate inside the otherwise domain-agnostic
CEF bridge (`core_ui` still doesn't know what a "credential" is - it only
forwards three named browser events verbatim) or inside a gameplay
resource (`gm_roleplay` has no knowledge of the auth UI at all - see the
resource responsibility table above). Its server-side half
(`AuthUiController.lua`) only reads `PlayerService.isAuthenticated` and
listens for `Events.PLAYER_ACCOUNT_RESOLVED` - both already exposed by
`core`'s existing exports/events - rather than absorbing `core`'s whole
server-side accounts domain (`AccountService`, `AccountEndpoints`, ...);
that split would add real resource-boundary risk (new exports/
`GlobalResources.lua` wiring on both sides, per gotcha #10 in
`AGENTS.md`) for no benefit today.

## UI architecture

See `UiBridge.md` for the full CEF↔MTA protocol. In summary:

- `core_ui/client/ui/BrowserManager.lua` owns the one long-lived CEF
  browser instance for the whole client session and centralizes cursor/
  input/control state through `UI.open(name)` / `UI.close(name)` /
  `UI.isOpen(name)`. No other client script should call
  `showCursor`/`guiSetInputEnabled`/`createBrowser` directly. Because
  `createBrowser` only produces an off-screen texture (not
  `guiCreateBrowser`, which would auto-render), this file also manually
  draws the browser fullscreen every frame via `dxDrawImage` and manually
  injects mouse move/click/wheel input - see the file's module comment
  for the full rationale and the exact injection calls required.
- `core_ui/client/ui/Transport.lua` is a pure relay between the browser
  and the server - it has no business logic.
- `packages/ui`'s `lib/mta/MtaBridge.ts` is the frontend's single entry
  point for talking to Lua (`mta.fetch`, `mta.on/off`, `mta.notify`). An
  `MtaTransport`/`BrowserDevTransport` pair lets the same frontend code
  run for real inside MTA or against a mock in a plain browser tab
  (`pnpm dev`).

## Database abstraction and the ORM

See `DatabaseContract.md` for the exact `Database.*` contract. In summary:
nothing in this project builds raw SQL by hand outside of `QueryBuilder.lua`
and `Schema.lua` - everything goes through `Database.query/queryOne/
execute/insert/transaction`, which delegate to whichever adapter called
`Database.registerAdapter(...)`.

- `MySqlAdapter.lua` - a real MySQL/MariaDB connection via MTA's native
  `dbConnect`/`dbQuery`/`dbExec`/`dbPoll` functions, the only adapter this
  project has. Connection details come from `core`'s `MYSQL_HOST`/
  `MYSQL_PORT`/`MYSQL_DATABASE`/`MYSQL_USERNAME`/`MYSQL_PASSWORD`/
  `MYSQL_CHARSET` settings (see the root README's "Attaching a real
  database" for the local Docker Compose setup). This project **does**
  own its MySQL implementation (unlike an earlier draft of this document,
  which deferred a PostgreSQL adapter to another developer) - MySQL is
  the committed backend, with a future migration to PostgreSQL possible
  but not planned work.

On top of `Database.*` sits a small Active Record ORM
(`core/server/orm/`):

- `Schema.lua` - declarative table/column definitions
  (`Model:extend(tableName, columns)` calls `Schema.define` internally).
  `Schema.migrate()` runs once at `MySqlAdapter` connection time, issuing
  `CREATE TABLE IF NOT EXISTS`/`ALTER TABLE ... ADD COLUMN` for every
  registered model - it never drops or alters an existing column, by
  design (a destructive schema change should be a deliberate, reviewed
  action, not a side effect of editing a model file).
- `QueryBuilder.lua` - fluent, `?`-parameterized query builder
  (`where`/`orderBy`/`limit`/`get`/`first`/`insert`/`update`/`delete`).
  Used directly by `Model.lua`; not normally called by application code.
- `Model.lua` - the Active Record base class. `Model:extend` defines a
  model; instances support `:save()`/`:delete()`; static methods support
  `Account:find(id, cb)`, `Account:where(col, val):first(cb)`,
  `Account:create(attrs, cb)`; `Model:hasMany`/`Model:belongsTo` declare
  relations as generated instance methods (e.g. `account:characters(cb)`).
  Every method is asynchronous/callback-based, matching `Database.*`'s
  contract end to end - there is no synchronous save/find anywhere.
- `Uuid.lua` - the one remaining app-side ID generator, used only for the
  `"uuid"` `Schema` column type (a plain, non-primary-key column) - not
  primary keys, which use MySQL `AUTO_INCREMENT` (`Schema`'s `"id"` type).

`AccountRepository.lua`/`CharacterRepository.lua` remain as thin facades
over the `Account`/`Character` models (`core/server/database/models/`) -
`AccountService` calls the repository, never the model/ORM directly, so
the facade stays the one place that would need to change if account
lookups ever needed something beyond the plain Active Record API.

## Adding a new system

1. Decide whether the new system needs to hand closures to/from `core`
   constantly (rare) or only needs plain-data exports/events (the common
   case). Default to a new resource under `systems/` or `gameplay/`.
2. Give it its own `meta.xml`, `server/GlobalResources.lua` (if it needs
   anything from `core_shared`, `core`, or `core_ui`), and organize files
   by responsibility (`XxxService.lua`, `XxxRepository.lua` if it needs
   its own persistence, `XxxEndpoints.lua` if it exposes FetchBridge
   endpoints - follow the `exports.core_ui:fetchBridgeRegisterMeta` +
   local `addEventHandler("endpoint:...", ...)` +
   `exports.core_ui:fetchBridgeRespond` pattern from `AccountEndpoints.lua`,
   see "FetchBridge across the core/core_ui boundary" above).
3. Never trust data arriving from client-side Lua or the browser -
   validate everything at the boundary (see `UiBridge.md`'s security
   section).
4. Add new shared constants (event names, error codes) to `core_shared`
   rather than inventing ad hoc strings in the new resource.
