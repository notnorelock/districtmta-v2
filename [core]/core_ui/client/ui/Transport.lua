-- Client-side relay between the CEF browser and the server FetchBridge/
-- PushService - see docs/UiBridge.md for the full protocol.

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

addEvent(Events.BROWSER_READY, true)
addEventHandler(Events.BROWSER_READY, root, function()
    if source ~= UI.getBrowser() then
        return
    end

    -- Harmless no-op if the session key hasn't arrived yet (two
    -- independent async handshakes) - see pushSessionKeyToBrowser's own guard.
    pushSessionKeyToBrowser()

    triggerServerEvent(Events.BROWSER_READY, localPlayer)
end)

-- "Remember me" credential persistence - stays domain-agnostic here,
-- just forwards the obfuscated payload to core_auth/client/
-- CredentialTransport.lua (see docs/Architecture.md).
for _, browserEventName in ipairs({ Events.CREDENTIALS_SAVE, Events.CREDENTIALS_LOAD, Events.CREDENTIALS_CLEAR }) do
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
