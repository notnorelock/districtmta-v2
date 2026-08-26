-- Client-side relay between the CEF browser and the server FetchBridge/
-- PushService - see docs/UiBridge.md for the full protocol.

-- See Events.UI_NOTIFY's own comment - the single channel every
-- MtaBridge.ts notify(eventName, ...args) call is routed through, so this
-- file is the only place that has to know window.mta.triggerEvent
-- stringifies every argument regardless of its real JS type. Re-fires the
-- real eventName via a plain triggerEvent(eventName, root, ...args) with
-- args already decoded back into real typed Lua values, for whichever
-- resource's own client Lua actually owns that event to pick up normally.
addEvent(Events.UI_NOTIFY, true)
addEventHandler(Events.UI_NOTIFY, root, function(eventName, argsJson)
    -- This IS the source == UI.getBrowser() check for every event relayed
    -- below - MtaBridge.ts's notify() now always routes through here (see
    -- Events.UI_NOTIFY's own comment), so nothing downstream re-checks
    -- source against the browser element itself; the re-fired
    -- triggerEvent(eventName, root, ...) below always sources from
    -- `root`, on purpose - it's a same-resource-tier relay, not a raw
    -- browser event a receiver needs to authenticate the origin of again.
    if source ~= UI.getBrowser() then
        return
    end
    if type(eventName) ~= "string" then
        return
    end

    -- MtaTransport.ts sends { args: [...] }, not a bare JSON array -
    -- MTA's own fromJSON auto-unwraps a top-level single-element JSON
    -- array back down to the bare value (fromJSON("[1]") returns the
    -- number 1, not a one-element table), so a bare array would silently
    -- lose its table-ness for exactly the single-argument case this
    -- project's events actually use. The { args = ... } wrapper sidesteps
    -- that unwrap - decoded is always a table with an "args" field.
    local ok, decoded = pcall(fromJSON, argsJson)
    local args = (ok and type(decoded) == "table" and decoded.args) or {}

    triggerEvent(eventName, root, unpack(args))
end)

addEvent(Events.UI_FETCH_REQUEST, true)
addEventHandler(Events.UI_FETCH_REQUEST, root, function(obfuscatedEnvelope)
    if source ~= UI.getBrowser() then
        return
    end

    -- Tries deobfuscating first, falls back to treating the payload as
    -- already-plaintext JSON - self-heals regardless of which side of
    -- the session-key handshake completed first (see docs/UiBridge.md).
    local envelope = nil
    local jsonEnvelope = deobfuscatePayload(obfuscatedEnvelope, SessionKeyState.key)
    if jsonEnvelope then
        envelope = fromJSON(jsonEnvelope)
    end

    if type(envelope) ~= "table" then
        envelope = fromJSON(obfuscatedEnvelope)
    end

    if type(envelope) ~= "table" then
        return
    end

    triggerServerEvent(Events.UI_FETCH_REQUEST, localPlayer, envelope)
end)

addEvent(Events.UI_FETCH_RESPONSE, true)
addEventHandler(Events.UI_FETCH_RESPONSE, root, function(requestId, response)
    local obfuscated = obfuscatePayload(toJsonValue(response or {}), SessionKeyState.key)
    local script = string.format(
        "window.__mtaFetchResponse && window.__mtaFetchResponse(%s, %s)",
        jsStringLiteral(requestId),
        jsStringLiteral(obfuscated)
    )
    UI.executeInBrowser(script)
end)

addEvent(Events.UI_PUSH_EVENT, true)
addEventHandler(Events.UI_PUSH_EVENT, root, function(eventName, data)
    local obfuscated = obfuscatePayload(toJsonValue(data or {}), SessionKeyState.key)
    local script = string.format(
        "window.__mtaPushEvent && window.__mtaPushEvent(%s, %s)",
        jsStringLiteral(eventName),
        jsStringLiteral(obfuscated)
    )
    UI.executeInBrowser(script)
end)

-- Fired by App.tsx's mta.notify("ui.ready") on mount, relayed here via
-- the UI_NOTIFY handler above (which already verified source ==
-- UI.getBrowser() before re-firing this with source == root) - not a
-- direct window.mta.triggerEvent("ui.ready", ...) call, so this handler
-- does not (and must not) re-check source against the browser element.
addEvent(Events.BROWSER_READY, true)
addEventHandler(Events.BROWSER_READY, root, function()
    -- Harmless no-op if the session key hasn't arrived yet (two
    -- independent async handshakes) - see pushSessionKeyToBrowser's own guard.
    pushSessionKeyToBrowser()

    triggerServerEvent(Events.BROWSER_READY, localPlayer)
end)

-- Remembered-account list persistence (login screen's account switcher)
-- and trusted-device bypass tokens - stays domain-agnostic here, just
-- forwards the obfuscated payload to core_auth/client/
-- AccountsTransport.lua / TrustedDeviceTransport.lua (see
-- docs/Architecture.md). Both families are forwarded through this SAME
-- loop (not two separate ones) since they're identical in shape: a
-- browser-sourced event carrying zero or one obfuscated-payload
-- argument, re-fired on `root` for core_auth's own resourceRoot-scoped
-- handler to pick up.
for _, browserEventName in ipairs({
    Events.ACCOUNTS_UPSERT, Events.ACCOUNTS_TOUCH, Events.ACCOUNTS_REMOVE, Events.ACCOUNTS_LIST,
    Events.TRUSTED_DEVICE_SAVE, Events.TRUSTED_DEVICE_LOAD, Events.TRUSTED_DEVICE_CLEAR,
}) do
    addEvent(browserEventName, true)
    addEventHandler(browserEventName, root, function(obfuscatedPayload)
        if source ~= UI.getBrowser() then
            return
        end

        -- Fired on `root`, not this resource's own resourceRoot, since
        -- core_auth's handler listens on ITS OWN resourceRoot - a
        -- different element, so `root` is the one element both share.
        triggerEvent(browserEventName, root, obfuscatedPayload)
    end)
end
