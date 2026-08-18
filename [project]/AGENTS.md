# AGENTS.md

Instructions for AI coding agents working in this repository. Read this
before making changes - several of the rules below exist because the
naive/obvious approach silently breaks in MTA and cost real debugging
time to discover.

## What this project is

Foundation for a Multi Theft Auto: San Andreas roleplay gamemode: MTA
resources in Lua (siblings of this directory, under
`mods/deathmatch/resources/` - `[core]`, `[gameplay]`, `[systems]`) plus
a SolidJS/TypeScript CEF frontend (`packages/ui/`, right here in
`[project]`). Not a finished gamemode - a working account/auth vertical
slice proving the architecture. See `docs/Architecture.md`,
`docs/DatabaseContract.md`, `docs/UiBridge.md` for full detail; this file
is the condensed, agent-facing version of the same rules.

**Where this file lives matters**: this whole directory
(`mods/deathmatch/resources/[project]/`) is itself a bracketed,
non-resource folder - MTA never loads anything inside it. It holds
everything that ISN'T an MTA resource (frontend source, docs, scripts,
this file) so the whole project stays in one repository even though the
repo root doubles as the MTA server's own runtime directory (`MTA
Server.exe` and its DLLs live there directly). The actual MTA Lua
resources live as siblings of this folder: `../[core]/core_bootstrap`,
`../[core]/core_shared`, `../[core]/core`, `../[core]/core_ui`,
`../[core]/core_auth`, `../[gameplay]/gm_roleplay`.

## The one rule that shapes everything else

**MTA cannot pass a live Lua function (closure) across a resource
boundary, in either direction, through any mechanism** - not
`exports`/`call` (confirmed against MTA server source: `CLuaArgument::Read`
nils out `LUA_TFUNCTION`, including nested inside tables, for both call
arguments and return values), and not `triggerEvent`/`addEventHandler`
either (same marshalling). This is why:

- `core_database` + `core_server` + `core_accounts` + database
  repositories + the account domain all live merged inside one resource,
  `core` - they pass callbacks to each other constantly
  (`AccountService.register(input, onSuccess, onError)` chains through
  several nested async repository calls).
- `core_ui` (the CEF bridge: `FetchBridge`, `PushService`,
  `BrowserManager`, `Transport`) is a *separate* resource from `core`,
  but is deliberately domain-agnostic - it never receives a handler
  closure from `core`. Endpoint owners register plain-data *metadata*
  with `core_ui` via exports, then handle the actual request locally via
  a plain custom event `core_ui` fires (carrying only `requestId` string,
  `player` element, `payload` table - never a function). See
  `core/server/accounts/AccountEndpoints.lua` for the reference pattern.

**When adding a new endpoint or cross-resource module:** if it needs to
hand a *callback* to another module, that module must live in the same
resource. If it only needs to exchange plain data or react to an event,
keep it in its own resource and use exports/events.

## MTA gotchas that will silently break things if you don't know them

These are not obvious from the API surface and produced real, hard-to-
diagnose bugs during development. Do not reintroduce them.

1. **`exports.resourceName:fn(...)` only resolves flat top-level global
   function names**, never a dotted path like `Database.query`. Every
   resource that consumes another resource's module has a
   `server/GlobalResources.lua` (and `client/GlobalResources.lua` where
   relevant), loaded first in meta.xml, which installs a
   `setmetatable(_G, {__index=...})` hook resolving a small set of global
   names to local proxy tables wrapping the target's flat exports. Follow
   this exact pattern for any new cross-resource dependency - see
   `core_ui/server/GlobalResources.lua` for a worked example.
2. **A table returned across an exports call loses its function
   *fields*** the same way function *arguments* are stripped - this is
   why `core_shared`'s `ValidationRules` splits into `getValidationRules()`
   (constants only) plus individually-exported flat functions
   (`validationRulesIsValidLogin`, ...) that consuming resources stitch
   back into one local table via a metatable.
3. **`mta.triggerEvent(...)` called from CEF browser JavaScript requires
   the target event to be registered with `addEvent(...)` on the client
   Lua side first** - exactly like `triggerClientEvent`/`triggerServerEvent`
   - but unlike those, an unregistered target fails **completely
   silently**: no Lua error, no JS error, the handler just never fires.
   Every browser→Lua event has an explicit `addEvent` directly above its
   `addEventHandler`.
4. **`toJSON(value)` always wraps its result in a top-level JSON array**,
   even for a single non-array value (documented MTA behavior - the same
   serializer backs event/export argument lists). Any Lua code embedding
   `toJSON(...)` output directly into a JS string must strip the outer
   `[ ]` first (`json:sub(2, -2)` after `toJSON(value, true)` for compact
   output) or the browser receives `[value]` instead of `value`.
5. **`base64Encode`/`base64Decode` are removed in current MTA** ("no
   longer works" runtime warning) - use `encodeString("base64", data,
   {})` / `decodeString("base64", encoded, {})` instead.
6. **`generateString` is not an MTA built-in** - the wiki page for it
   documents a community-contributed snippet, not native API. Calling it
   unqualified throws `attempt to call global 'generateString' (a nil
   value)`. If you need a random string, implement it yourself (see
   `core/server/SessionKeyService.lua` for a working version) and seed
   `math.random` once, not per-call.
7. **`createBrowser()` only produces an off-screen texture** - it does
   NOT render to the screen (that's `guiCreateBrowser`'s job). A
   `createBrowser` element needs manual `dxDrawImage` every frame
   (`onClientRender`) plus manual input injection: cursor via
   `injectBrowserMouseMove`, clicks via `injectBrowserMouseDown`/`Up` (NOT
   automatic - only keyboard is, once `focusBrowser` is called), and
   scroll via `injectBrowserMouseWheel` (surfaces through `onClientKey`
   with `"mouse_wheel_up"`/`"mouse_wheel_down"`, not a dedicated event).
   See `core_ui/client/ui/BrowserManager.lua`.
8. **Resource start order matters and restarts don't always cascade.**
   `<include resource="...">` in meta.xml is a start-order hint only, not
   a hard dependency gate, and does not share code/globals. If resource A
   registers something with resource B at A's own script-load time, and A
   starts before B is running, that call silently no-ops. If B restarts
   on its own later (common during development) while A keeps running,
   anything B held in memory is gone and A needs to notice and
   re-register. See `core/server/accounts/AccountEndpoints.lua` for the
   pattern that handles both directions (register immediately if the
   target is already running, AND keep listening for the target's
   `onResourceStart` for the rest of this resource's lifetime). On a full
   server boot (or manual restart of the whole chain), the correct order
   is enforced by `core_bootstrap` - it is the only project resource with
   `startup="1"` in `mtaserver.conf`, and it starts the rest itself, one
   at a time, waiting for each `onResourceStart` before starting the
   next. See `core_bootstrap/server/Bootstrap.lua`.
9. **Each `<script>` in meta.xml is its own Lua chunk** - a `local`
   declared in one file is invisible to another file in the same
   resource, even though they share one Lua VM/`_G`. Cross-file sharing
   within a resource needs a real global (see `core_ui/client/ui/SessionKeyState.lua`
   for a minimal example) or a table assigned without `local`.
10. **A cross-resource `exports` call that itself calls back into the
    resource that originated it (re-entrant export chain) can fail even
    when every resource involved is genuinely running.** Concretely: `core`
    calls `exports.core_ui:fetchBridgeRegisterMeta(...)`; if that function,
    running inside `core_ui`, then calls `exports.core:loggerDebug(...)`
    (re-entering `core` while `core`'s own call stack is still on the way
    down into `core_ui`), the callee side's own `isResourceAvailable(...)`-
    style check on the *originating* resource can read `false` - not at
    startup, on every single call, reproducibly. This is why `core_ui` has
    its own local `Logger.lua` (`core_ui/server/Logger.lua`) instead of
    proxying to `core`'s, unlike every other cross-resource dependency in
    this project. If you add a new `core_ui`-internal call that would
    re-enter `core` (or vice versa) from inside an already-cross-resource
    call, duplicate the logic locally rather than proxying - don't assume
    the proxy pattern that works for `PlayerService`/`SecurityService` (one-
    directional calls, not part of a re-entrant chain) is safe to copy
    blindly for something that can be called FROM the resource it would
    call back INTO.
11. **Server-side start order (core_bootstrap) says nothing about
    CLIENT-side script timing for already-connected players.** A resource
    finishing `onResourceStart` on the server only means its server-side
    scripts ran - each connected client independently downloads and
    starts that resource's `type="client"`/`"shared"` scripts on its own
    schedule. A client script that reads a proxied global (`Events.X`,
    `Enums.X`) at its own MODULE load time (e.g. a bare top-level
    `addEvent(Events.X, true)`, not one inside a handler) gets exactly ONE
    read attempt - if `core_shared`'s client-side scripts haven't started
    on that particular client yet, the read resolves to `false` (the
    `GlobalResources.lua` metatable pattern's designed fallback for "not
    available yet"), indexing it throws, and the WHOLE REST of that file
    silently never runs (every later `addEvent`/`addEventHandler` call in
    the same chunk is skipped). This is different from gotcha #10 above -
    it's a client-side timing race, not a re-entrant export call.
    `core_bootstrap`'s `STEP_DELAY_MS` (see `core_bootstrap/server/Bootstrap.lua`)
    is the current mitigation - a pause between starting each resource in
    the chain, giving already-connected clients a moment to catch up on
    the previous resource's client-side scripts before the next one's
    arrive. It's a pragmatic buffer, not a real guarantee - a slow/high-
    latency client could still lose the race and hit this. If it comes up
    again, the actually-correct fix is making the affected client script
    retry instead of reading the proxied global once at module load time.
12. **In-memory server state does not survive a resource restart, even
    though a connected player's session does.** `core/server/PlayerService.lua`'s
    `accountContexts` table is scoped to `core`'s own Lua VM - restarting
    `core` alone (or the whole chain via `core_bootstrap`/`/restartchain`,
    e.g. after a code change) wipes it, but every already-connected
    player stays connected the whole time (this is a resource restart,
    not a disconnect). Without recovery, every already-logged-in player
    would be silently kicked back to the login screen despite never
    having left. The fix pattern: persist just enough state as **element
    data** on the player element itself (`setElementData`), which - unlike
    a resource-local Lua table - survives that resource restarting, since
    it lives on the element, not in any one resource's VM. See
    `core_auth/server/AuthUiController.lua`'s `player:logged`/`account:*`
    (set on first successful login) and `gm_roleplay/server/GameplayBootstrap.lua`'s
    `player:spawned` (set once `spawnPlayer` actually runs), both read
    back by `PlayerService.lua`'s `onResourceStart` handler
    (`reconnectAlreadyLoggedInPlayers`) to silently re-establish
    `accountContexts` without re-showing the login screen or (if the
    player had already spawned) re-triggering spawn-select. Any future
    resource-local runtime cache with the same "must survive this
    resource's own restart, but not a real disconnect" requirement should
    use the same element-data pattern rather than trying to persist state
    some other way.

## Database and ORM

Nothing builds raw SQL by hand outside `core/server/orm/QueryBuilder.lua`/
`Schema.lua`. Everything goes through `Database.query/queryOne/execute/
insert/transaction` (`core/server/database/DatabaseAdapter.lua`), which
delegates to whichever adapter called `Database.registerAdapter(...)` -
`MySqlAdapter.lua` (real MySQL/MariaDB via MTA's native `dbConnect`/
`dbQuery`/`dbExec`/`dbPoll`), the only adapter this project has; there is
no in-memory fallback, a real database (see root README's "Attaching a
real database") must be reachable for `core` to start up usefully. **MySQL
is this project's own, committed database backend** - unlike an earlier
draft of this project, there is no external developer waiting to supply a
PostgreSQL driver; `MySqlAdapter.lua` is the real thing.

On top of `Database.*` sits a small Active Record ORM
(`core/server/orm/Model.lua`/`QueryBuilder.lua`/`Schema.lua`):
`Model:extend(tableName, columns)` defines a model and its schema in one
call; `Schema.migrate()` (run once at `MySqlAdapter` connection time)
creates/updates tables automatically - **it never drops or alters an
existing column**, so a destructive schema change must be done
deliberately, not via a model edit. Primary keys use `Schema`'s `"id"`
type (MySQL `AUTO_INCREMENT`), not app-generated UUIDs - `Uuid.lua`
remains available for the `"uuid"` column type on ordinary (non-primary-
key) columns only. See `docs/DatabaseContract.md` for the full ORM API
and the exact `Database.*` adapter contract.

## Accounts

Real login/email + password authentication. Passwords are hashed with
MTA's **native** `passwordHash`/`passwordVerify` (bcrypt, `"$2y$"` format -
see https://wiki.multitheftauto.com/wiki/PasswordHash) in their
async/callback form - the synchronous form blocks the entire server
process for the duration of the bcrypt computation, which MTA's own docs
warn against. Never hand-roll password hashing, never log or send a
plaintext password anywhere past `AccountService.register`/`.login`'s
single point of use, and never include `password_hash` in
`AccountService.toPublic`'s browser-facing DTO.

MTA's own `getPlayerSerial(player)` (stored as `mta_serial` on the account
row) is a "recognize this client" convenience only, rebound on every
successful login - it is **not** the authentication credential and must
never be treated as sufficient proof of identity on its own (MTA serials
are not cryptographically unforgeable). The password is the real
credential.

## Security boundary

Everything arriving from CEF or client-side Lua is untrusted input.
`FetchBridge` (`core_ui/server/FetchBridge.lua`) validates request id,
endpoint name, argument shape, authentication state, and rate limits
before dispatching. Never trust `accountId`, money, permissions, admin
level, or any authority-bearing value if it originates from the browser -
resolve it from server-side state (`PlayerService.getAccount(player)`).

The CEF↔Lua leg is XOR+base64 **obfuscated** with a per-player session
key (see `docs/UiBridge.md`'s "Payload obfuscation" section) - this is
explicitly not encryption or authentication and does not replace
`FetchBridge`'s validation. Do not reason about it as a real security
boundary, and do not extend this pattern to anything that actually needs
confidentiality/integrity guarantees.

## Frontend (`packages/ui`)

SolidJS + TypeScript + Webpack + Tailwind CSS v4. React patterns
(`useState`, `useEffect`, `React.memo`) are wrong here - use Solid's
fine-grained reactivity (`createSignal`, `createStore`, `createMemo`,
`createEffect`, `onCleanup`, `Show`/`For`/`Switch`/`Match`). No Redux, no
context overuse. Frontend stores mirror server state, they are not
authoritative.

`mta.fetch`/`mta.on`/`mta.notify` (`lib/mta/MtaBridge.ts`) is the only
entry point to Lua - never spread raw endpoint strings across components,
wrap them in domain-specific API modules (`lib/api/authApi.ts`, etc.).
`MtaTransport` (real MTA) and `BrowserDevTransport` (plain browser,
`pnpm dev`) share one interface (`MtaTransportLike`) so the same frontend
code runs in both; `isMtaEnvironment()` in `lib/mta/environment.ts`
selects between them once, at module load - don't add ad hoc environment
checks elsewhere.

### UI components (`components/ui/*.tsx`)

Ported by hand from [solid-ui](https://github.com/stefan-karger/solid-ui)
(a shadcn/ui equivalent for SolidJS, built on Kobalte - the Solid analog
of Radix UI). **Do not run solid-ui's own CLI** (`npx solidui-cli add ...`)
against this project - as of this writing it scaffolds Tailwind v3 config
(`hsl(var(--x))` tokens, `tailwind.config.cjs`) and would overwrite
`styles/globals.css`'s Tailwind v4 `@theme` setup. To add a new component
from solid-ui: fetch its source directly from
`github.com/stefan-karger/solid-ui` (`apps/docs/src/registry/ui/*.tsx`),
copy it into `components/ui/`, and rewrite every class name from v3
`hsl(var(--x))`/`tailwind.config.cjs` tokens onto this project's `@theme`
tokens in `styles/globals.css` (they follow shadcn's semantic naming
convention - `bg-primary`, `text-muted-foreground`, `border-input`,
`ring-ring`, etc. - so most class strings carry over unchanged). Custom,
non-shadcn tokens (`accent-indigo`, `accent-violet`) must be registered in
`lib/cn.ts`'s `extendTailwindMerge` call or `cn()` silently fails to dedupe
them against conflicting classes - see that file's own comment for a real
bug this caused (a stray gold ring/button color surviving a merge because
`tailwind-merge` didn't know the custom token was a color).

`tw-animate-css` (imported in `styles/globals.css`) is the Tailwind v4
replacement for the `tailwindcss-animate` plugin solid-ui's own
dialog/toast/select animations assume - without it, `animate-in`/
`fade-in`/`zoom-in-95`/`slide-in-from-*` classes are silently inert (no
error, the element just doesn't animate). If a newly-ported component's
animation doesn't seem to work, check this import exists before assuming
the component itself is broken.

After any frontend change meant to be visible in-game, run
`node scripts/build-ui.mjs` from this directory (`[project]/`) - `pnpm
build` alone only writes to `packages/ui/dist/`, it does not update what
`core_ui` actually serves to players. Then restart `core_ui` in-game.

## Commands

All from `mods/deathmatch/resources/[project]/` (this directory):

```bash
cd packages/ui && pnpm install   # first time only
pnpm dev                          # preview in a plain browser tab (mocked transport)
pnpm typecheck                    # tsc --noEmit
pnpm build                        # production build into packages/ui/dist

# from [project]/ itself (not packages/ui), after any frontend change meant for in-game use:
node scripts/build-ui.mjs         # builds + copies into ../[core]/core_ui/client/html
```

No automated Lua test suite exists (no MTA server harness in this
environment) - verify Lua changes by static review (script order in
meta.xml, exports/addEvent pairing, no stray `local` where a global is
needed) and, when actually testing in-game, by checking the F8 debug
console and `/browserdebug` (opens real CEF DevTools against the live
browser).
