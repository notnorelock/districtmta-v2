# UI Bridge

This document explains the CEF ↔ MTA Lua communication protocol: how a
request travels from a SolidJS component to a server-side handler and
back, how server-pushed events reach the browser, and the security model
that prevents the browser from becoming an arbitrary code execution
primitive against the server.

The bridge spans two MTA resources - `core_ui` (the generic, domain-
agnostic router) and `core` (which owns every actual endpoint handler).
See `docs/Architecture.md` for why the split works despite MTA not being
able to pass Lua closures across resource boundaries.

## Layers

```
SolidJS component
     |  authApi.register({ login, email, password })   (packages/ui/src/lib/api)
     v
mta.fetch<T>(endpoint, args, options)         (packages/ui/src/lib/mta/MtaBridge.ts)
     |  builds { id, endpoint, arguments, ts }, tracks a pending Promise
     v
MtaTransport.send(envelope)                   (packages/ui/src/lib/mta/MtaTransport.ts)
     |  obfuscatePayload(JSON.stringify(envelope), sessionKey)  -- see "Payload obfuscation" below
     |  window.mta.triggerEvent("ui:fetchData", obfuscatedEnvelope)
     v
core_ui/client/ui/Transport.lua               addEventHandler("ui:fetchData", ...)
     |  deobfuscatePayload, fromJSON, triggerServerEvent(Events.UI_FETCH_REQUEST, localPlayer, envelope)
     v
core_ui/server/FetchBridge.lua                addEventHandler(Events.UI_FETCH_REQUEST, ...)
     |  validate envelope -> resolve endpoint metadata -> authenticated? -> rate limited?
     |  -> triggerEvent("endpoint:" .. name, resourceRoot, requestId, player, payload)
     v
core/server/accounts/AccountEndpoints.lua     addEventHandler("endpoint:auth.register", ...)
     |  (runs inside core - can call AccountService/Database/etc. freely)
     |  exports.core_ui:fetchBridgeRespond(requestId, {success, data} | {success, error})
     v
core_ui/server/FetchBridge.lua                looks up the pending request by id
     |  triggerClientEvent(player, Events.UI_FETCH_RESPONSE, ...)
     v
core_ui/client/ui/Transport.lua               addEventHandler(Events.UI_FETCH_RESPONSE, ...)
     |  obfuscatePayload(toJsonValue(response), sessionKey)
     |  executeBrowserJavascript(browser, "window.__mtaFetchResponse(id, obfuscatedResponse)")
     v
MtaTransport (browser side)                   window.__mtaFetchResponse installed by MtaTransport.onResponse
     |  deobfuscatePayload, JSON.parse
     v
MtaBridge.fetch's pending Promise resolves with MtaResponse<T>
     v
SolidJS store/component updates
```

Note the handoff at the `core_ui` → `core` step: `FetchBridge` never
hands the endpoint owner a closure-bearing "ctx" object (that would
require passing a live function across the resource boundary, which MTA
cannot do). Instead it triggers a plain event carrying only `requestId`
(string), `player` (element - elements survive the marshalling boundary
fine, only functions/coroutines don't), and `payload` (plain JSON-shaped
data). The endpoint owner reports its result the same way in reverse, by
calling back into `core_ui`'s exports with a plain response table.

Server-pushed events (not initiated by a browser request) use a parallel,
explicitly separate channel:

```
NotificationService.send(player, {...})       (core/server/notifications/NotificationService.lua)
     |  exports.core_ui:pushServiceSend(player, event, data)  -- plain data only
     v
PushService.send(player, event, data)         core_ui/server/PushService.lua
     |  triggerClientEvent(player, Events.UI_PUSH_EVENT, resourceRoot, event, data)
     v
core_ui/client/ui/Transport.lua               addEventHandler(Events.UI_PUSH_EVENT, ...)
     |  executeBrowserJavascript(browser, "window.__mtaPushEvent(event, data)")
     v
MtaTransport (browser side)                   window.__mtaPushEvent installed by MtaTransport.onPush
     v
MtaBridge dispatches to any mta.on(event, handler) subscribers
```

RPC responses and pushed events deliberately use different JS entry points
(`__mtaFetchResponse` vs `__mtaPushEvent`) and different MTA custom events
(`UI_FETCH_RESPONSE` vs `UI_PUSH_EVENT`) so the frontend never has to guess
whether an incoming message is "the answer to something I asked" or "the
server telling me something unprompted."

## Request envelope

```ts
interface MtaFetchRequestEnvelope {
  id: string;        // crypto.randomUUID(), correlation only - not a credential
  endpoint: string;  // e.g. "auth.register" - must match a registered endpoint
  arguments: unknown[];
  ts: number;
}
```

`id` only correlates a request with its response. It carries no authority
- do not confuse it with a session token or treat it as proof of anything.
`crypto.randomUUID()` is used where available; `MtaBridge.ts` falls back to
a timestamp+random string if not.

## Response envelope

```ts
type MtaResponse<T> =
  | { success: true; data: T }
  | { success: false; error: { code: ApiErrorCode; message?: string } };
```

`error.message`, when present, must be safe to show a player - never a raw
Lua error or SQL error string. Internal exceptions raised inside an
endpoint handler are the endpoint owner's responsibility to catch and map
to a safe error code before calling `exports.core_ui:fetchBridgeRespond`
- `core_ui`'s `FetchBridge` itself only maps its own validation failures
(malformed envelope, unknown endpoint, unauthenticated, rate limited) to
error codes directly; it has no visibility into what happens inside a
handler running in a different resource.

### Error codes

Defined once in `core_shared/shared/ErrorCodes.lua` and mirrored (not
imported - Lua and TypeScript can't share types across the language
boundary) in `packages/ui/src/types/api.ts` as `ApiErrorCode`:

```
INVALID_REQUEST, INVALID_ARGUMENTS, INVALID_LOGIN, INVALID_EMAIL,
INVALID_PASSWORD, INVALID_CREDENTIALS, NOT_AUTHENTICATED,
ACCOUNT_NOT_FOUND, ACCOUNT_ALREADY_EXISTS, RATE_LIMITED, REQUEST_TIMEOUT,
INTERNAL_ERROR, RESOURCE_UNAVAILABLE, UNKNOWN_ENDPOINT
```

The frontend's `i18n` dictionaries have an `auth.error.<CODE>` key for
each of these (see `packages/ui/src/i18n/pl.ts` / `en.ts`); `AuthCard.tsx`
looks up `auth.error.${code}` and falls back to the key itself if a
translation is missing (see `t()` in `packages/ui/src/i18n/index.ts`).

## Endpoint registry (security boundary)

The browser can **only** reach endpoints explicitly registered via a
two-step process, split across the resource boundary:

```lua
-- 1. core/server/accounts/AccountEndpoints.lua registers metadata with
--    core_ui - plain data only, crosses via exports:
exports.core_ui:fetchBridgeRegisterMeta("account.current", {
    authenticated = true,
    rateLimit = { limit = 20, intervalMs = 10000 },
})

-- 2. The actual handler is a local event listener inside core - never
--    exposed to core_ui at all:
addEvent("endpoint:account.current", true)
addEventHandler("endpoint:account.current", root, function(requestId, player, payload)
    local account = PlayerService.getAccount(player)
    exports.core_ui:fetchBridgeRespond(requestId, { success = true, data = AccountService.toPublic(account) })
end)
```

There is no code path by which a browser-supplied endpoint string gets
concatenated into an event name and blindly triggered as arbitrary code -
`core_ui`'s `FetchBridge` looks the name up in its own metadata registry
(`endpointMeta`, private to `FetchBridge.lua`) before it will fire
anything, and the `"endpoint:" .. name` event it fires afterward carries
no code, only plain data. An unknown endpoint returns `UNKNOWN_ENDPOINT`
and calls `SecurityService.report(player, "UNKNOWN_ENDPOINT", { endpoint
= ... })` (see the anti-cheat hook section below) without ever touching
the `"endpoint:"` event namespace.

A new gameplay/system resource that wants its own endpoints follows the
exact same two-step pattern from its own resource - it does not need to
be merged into `core`. Only modules that need to hand *closures* to each
other (not just register metadata and report back with plain data) need
to share a resource - see `docs/Architecture.md`.

## Handler contract

```lua
addEventHandler("endpoint:<name>", root, function(requestId, player, payload)
    -- requestId    string, pass through to fetchBridgeRespond unchanged
    -- player       the requesting player element (authoritative - never
    --               trust anything the browser claims about identity)
    -- payload      the single argument the browser sent, or nil

    exports.core_ui:fetchBridgeRespond(requestId, { success = true, data = ... })
    -- or:
    exports.core_ui:fetchBridgeRespond(requestId, { success = false, error = { code = ..., message = ... } })
end)
```

A handler may respond synchronously or from any later callback (a
`Database.*` call, a timer, another async operation) - `fetchBridgeRespond`
can be invoked from anywhere as long as it happens **exactly once** for a
given `requestId`. `FetchBridge` (in `core_ui`) tracks `responded` per
request and silently drops (with a `Logger.warn`) any second response for
the same request id.

## Request lifecycle & cleanup

Each accepted request is tracked in `core_ui`'s `FetchBridge` as:

```lua
{ player, endpoint, createdAt, responded = false }
```

Requests are removed from the pending table on:
- a successful or error response (`FetchBridge.respond`),
- a 15-second timeout (`REQUEST_TIMEOUT_MS` in `FetchBridge.lua`), which
  resolves the browser's Promise with `{ success = false, error = { code:
  "REQUEST_TIMEOUT" } }`,
- the requesting player quitting (`onPlayerQuit`),
- the resource stopping (`onResourceStop`, which clears the whole table).

This prevents unbounded growth of the pending-requests table if a handler
never responds or a player disconnects mid-request. Note this also means
if `core` (the endpoint owner) crashes or stops after `core_ui` dispatched
a request but before it responds, the browser simply times out after 15
seconds rather than hanging forever.

## Rate limiting

Each endpoint has a `rateLimit = { limit, intervalMs }` (default: 30
requests per 10 seconds if unspecified), supplied at registration time via
`fetchBridgeRegisterMeta`. `FetchBridge` tracks a simple fixed-window
counter per `(player, endpoint)` pair. Exceeding the limit returns
`RATE_LIMITED` immediately - it does not ban or otherwise penalize the
player; a single legitimate double-click should never escalate beyond a
rejected request.

## Anti-cheat integration hook

`SecurityService.report(player, code, metadata)` lives in `core`
(`core/server/SecurityService.lua`) and is exported as
`securityServiceReport` for `core_ui` to call. `core_ui`'s `FetchBridge`
calls it whenever it sees a malformed envelope or an unknown endpoint. It
logs via `Logger.security` and fires a plain custom event
(`core:security.report`) that a future dedicated anti-cheat resource can
subscribe to without `core` depending on that resource existing. No
detection logic is implemented here - this is purely the hook point.

## Security rules (non-negotiable)

Everything arriving from CEF or client-side Lua is untrusted input. The
bridge validates, at minimum:

- **Request id**: must be a non-empty string, capped length.
- **Endpoint name**: must be a non-empty string, capped length, and must
  match a registered endpoint.
- **Arguments**: must be an array, capped count (`ValidationRules.MAX_ARGUMENT_COUNT`).
- **Authentication state**: resolved from `PlayerService.isAuthenticated(player)`
  server-side (via `core`'s exported `playerServiceIsAuthenticated`) -
  never from anything the payload claims.
- **Payload shape/values**: endpoint handlers and `AccountService`/
  `ValidationRules` validate login/email format, length, etc. before
  touching the database.

Never trust `accountId`, money, permissions, admin level, character id,
ownership, or any other authority-bearing value if it originates from the
browser. Resolve all of that from server-side state
(`PlayerService.getAccount(player)`, database lookups keyed by the
server's own player element) - never from a client-supplied field.

## Payload obfuscation (not encryption)

Every payload on the browser ↔ Lua leg specifically (`ui:fetchData`,
`window.__mtaFetchResponse`, `window.__mtaPushEvent` - not the Lua
server ↔ client leg, which is a trusted native MTA channel a player
cannot inspect from CEF devtools) is XOR'd with a per-player session key
and base64-encoded before it's embedded in a `triggerEvent`/
`executeBrowserJavascript` call:

```
plaintext JSON  --(UTF-8 bytes XOR sessionKey)-->  ciphertext bytes  --(base64)-->  transport string
```

**This is obfuscation, not encryption, and does not provide
confidentiality or integrity guarantees:**

- The session key has to reach the browser to be usable there (see
  below), so anyone with access to CEF devtools, the page's JS console,
  or the client process's memory can recover it and decode/forge
  payloads freely. XOR with a key the attacker can obtain is not
  cryptographically secure - do not reason about this layer as if it
  were.
- It does **not** replace server-side validation. `FetchBridge` validates
  every field of a decoded envelope exactly as if this layer didn't
  exist. The only thing this layer buys is raising the bar above "read or
  edit the request in the Network/Console tab with zero effort" -
  primarily anti-tampering *friction*, not an anti-tampering *guarantee*.
- Never use this pattern for a value that actually needs confidentiality
  or integrity - if something needs a real guarantee, it needs real
  cryptography (and, more importantly, server-side authorization checks
  that don't depend on the client not having seen a value).

### Session key lifecycle

The key is per-player state, generated fresh on every `onPlayerJoin` by
`core/server/SessionKeyService.lua` (lives alongside `PlayerService`,
not in `core_ui`, since it's the same category of per-player state) and
exported as `getSessionKey(player)`. `core_ui/server/SessionKeyDelivery.lua`
reads it (with a short retry loop, since resource-to-resource
`onPlayerJoin` handler ordering across `core` and `core_ui` is not
guaranteed) and delivers it to client Lua over `triggerClientEvent` -
already a trusted channel, so this hop is not itself obfuscated.
Client-side, `core_ui/client/ui/Transport.lua` receives the key and
injects it into the browser exactly once via
`window.__mtaSessionKey = '...'` - this one call is the necessary
bootstrap exception, since something has to hand the key over in the
clear before either side can obfuscate anything.

Until the key has arrived (a brief window right after the browser loads,
before both independent async handshakes - `ui.ready` and the session key
delivery - complete), `obfuscatePayload`/`deobfuscatePayload` on both
sides pass their input through unchanged rather than failing (see the
`if not key then return plaintext` guard in
`core_ui/client/ui/PayloadObfuscation.lua` and the matching `if (!key)`
guard in `packages/ui/src/lib/mta/payloadObfuscation.ts`). This is safe
by construction - both sides degrade to plaintext together - but it does
mean the very first request or two after a browser (re)load may not be
obfuscated. If `core_ui` restarts (recreating the browser and clearing
`SessionKeyState.key`) while `core`'s key for that player is unaffected,
a brief mismatch window is possible for the same reason; see "Resource
restart behavior" below - a full browser reload resolves it, same as
other post-restart desync cases.

### Where the implementation lives

- `core_ui/client/ui/PayloadObfuscation.lua` / `packages/ui/src/lib/mta/payloadObfuscation.ts` -
  the XOR+base64 helpers, written to produce byte-identical output on
  both sides. Getting this byte-exact matters: Lua strings are raw byte
  arrays, JS strings are UTF-16 code units, so the TypeScript side
  explicitly UTF-8 encodes/decodes via `TextEncoder`/`TextDecoder` rather
  than operating on UTF-16 code units directly - otherwise any non-ASCII
  character (an accented login, a translated error message) would
  silently corrupt across the boundary.
- `core_ui/client/ui/SessionKeyState.lua` - a tiny shared global holding
  the current key, since `BrowserManager.lua` (which also sends
  obfuscated push messages directly, for `UI.open`/`UI.close`) and
  `Transport.lua` are separate Lua chunks (each meta.xml `<script>` is
  its own chunk - see `docs/Architecture.md`) and can't share a `local`.
- `core/server/SessionKeyService.lua` / `core_ui/server/SessionKeyDelivery.lua` -
  key generation and delivery, described above.

## Browser lifecycle

`core_ui/client/ui/BrowserManager.lua` creates **one** CEF browser on
`onClientResourceStart` and reuses it for the client's entire session -
windows are never recreated per open/close. `UI.open(name)` / `UI.close(name)`
/ `UI.isOpen(name)` centrally manage cursor visibility, input mode, and
control blocking so that no two features fight over `showCursor`/
`guiSetInputEnabled` independently; every `UI.open`/`UI.close` call also
pushes a `ui.open`/`ui.close` push event into the browser (same
`__mtaPushEvent` channel notifications use) so the SolidJS `ui.store.ts`
can react to which named window should currently be visible.

`createBrowser` (unlike `guiCreateBrowser`) only produces an off-screen
texture/material element - it does not render to the screen by itself.
`BrowserManager.lua` therefore manually draws it fullscreen every frame
via `dxDrawImage` in an `onClientRender` handler, and manually forwards
input into it since a plain `createBrowser` element doesn't participate
in MTA's GUI input system either:
- **Cursor position**: `injectBrowserMouseMove(browser, x, y)`, called
  only when the position actually changed since the last frame.
- **Clicks**: MTA does **not** automatically route mouse clicks to a
  `createBrowser` element (only keyboard input is automatic, once
  focused) - `onClientClick` is hooked and re-injects via
  `injectBrowserMouseDown`/`injectBrowserMouseUp`.
- **Scroll**: the wheel surfaces as a regular key
  (`"mouse_wheel_up"`/`"mouse_wheel_down"`) through `onClientKey`, not a
  dedicated mouse-wheel event - re-injected via `injectBrowserMouseWheel`.
- **Focus**: `focusBrowser(browser)` / `focusBrowser(nil)` is called only
  when the open/closed state actually changes, not every frame - it's a
  state-setting call.

Until the browser's document is ready, any `executeBrowserJavascript`
calls are queued (`queuedMessages` in `BrowserManager.lua`) and flushed
once `onClientBrowserDocumentReady` fires. Separately, the frontend itself
signals real readiness once SolidJS has mounted by calling
`mta.notify("ui.ready")` (see `packages/ui/src/App.tsx`), which is a raw
fire-and-forget browser event distinct from the FetchBridge RPC channel -
there is no `"ui.ready"` FetchBridge endpoint.

Run `/browserdebug` in the F8 console to open real CEF DevTools against
the live browser instance (`toggleBrowserDevTools`) - the fastest way to
inspect actual JS console/network state when diagnosing a bridge issue.

## Two MTA gotchas that silently break this bridge if missed

These cost real debugging time building this project and are easy to
reintroduce by accident when adding a new browser↔Lua event:

1. **`mta.triggerEvent(...)` from CEF requires `addEvent(...)` on the Lua
   side first**, exactly like `triggerClientEvent`/`triggerServerEvent` -
   but unlike those, an unregistered target fails **completely silently**:
   no Lua error, no JS error, the handler just never fires. Every
   browser→Lua event in this project (`ui:fetchData`, `ui.ready`) has an
   explicit `addEvent` call directly above its `addEventHandler`.
2. **`toJSON(value)` always wraps its result in a top-level JSON array**,
   even for a single non-array value (documented MTA behavior - the same
   serializer backs event/export argument lists). Any Lua code that embeds
   `toJSON(...)` output directly into a `executeBrowserJavascript` string
   must strip the outer `[ ]` first, or the browser receives `[value]`
   instead of `value`. See the `toJsonValue` helper in
   `core_ui/client/ui/Transport.lua` and `BrowserManager.lua`.

## Environment detection & local development

`packages/ui/src/lib/mta/environment.ts`'s `isMtaEnvironment()` checks for
`window.mta.triggerEvent` to decide which transport to use:

- **`MtaTransport`**: the real bridge described above, used inside MTA's
  CEF.
- **`BrowserDevTransport`**: used when the app runs in a plain browser tab
  (`pnpm dev`). It fakes just enough of `FetchBridge`'s behavior (with an
  artificial delay) to exercise the auth vertical slice without launching
  GTA:SA - see `packages/ui/src/lib/mta/BrowserDevTransport.ts`. It is not
  a general-purpose mock server.

Both implement the same `MtaTransportLike` interface
(`packages/ui/src/lib/mta/Transport.ts`), and `MtaBridge` (the only
consumer of that interface) never branches on environment itself - the
transport selection happens once, at module load, in `MtaBridge.ts`.

## Resource restart behavior

If `core_ui` restarts, `BrowserManager`'s browser instance is destroyed
and recreated (`onClientResourceStop`/`onClientResourceStart`), and any
pending FetchBridge requests are lost (the browser's Promises for those
requests will simply time out after 15 seconds and resolve as
`REQUEST_TIMEOUT`). If `core` restarts instead, `core_ui` keeps running
and the browser stays up, but any endpoint whose owner just restarted will
fail with `UNKNOWN_ENDPOINT` until that resource's `AccountEndpoints.lua`
(or equivalent) re-registers its metadata on startup. The frontend's own
state (`authStore`, etc.) is not automatically resynchronized in either
case - a full page reload of the CEF browser is required to re-run
`mta.notify("ui.ready")` and `authStore.checkStatus()`. This is a known,
documented limitation rather than something silently papered over.
