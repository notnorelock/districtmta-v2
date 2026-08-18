-- toJSON() always wraps its argument in a top-level JSON array - stripped
-- before embedding into a JS string (see docs/Architecture.md).
local function toJsonValue(value)
    local json = toJSON(value, true)
    return json:sub(2, -2)
end

addEvent(Events.CREDENTIALS_SAVE, true)
addEventHandler(Events.CREDENTIALS_SAVE, root, function(obfuscatedPayload)
    local jsonPayload = exports.core_ui:uiDeobfuscateFromBrowser(obfuscatedPayload) or obfuscatedPayload
    local payload = fromJSON(jsonPayload)

    if type(payload) ~= "table" or type(payload.login) ~= "string" or type(payload.password) ~= "string" then
        outputDebugString("CredentialTransport: received malformed credentials.save payload", 2)
        return
    end

    CredentialStore.save(payload.login, payload.password)
end)

addEvent(Events.CREDENTIALS_CLEAR, true)
addEventHandler(Events.CREDENTIALS_CLEAR, root, function()
    CredentialStore.clear()
end)

addEvent(Events.CREDENTIALS_LOAD, true)
addEventHandler(Events.CREDENTIALS_LOAD, root, function()
    local login, password = CredentialStore.load()
    local response = { login = login, password = password }

    local obfuscated = exports.core_ui:uiObfuscateForBrowser(toJsonValue(response))
    local script = string.format(
        "window.__mtaCredentialsLoaded && window.__mtaCredentialsLoaded(%s)",
        ("'%s'"):format(tostring(obfuscated):gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", ""))
    )
    exports.core_ui:uiExecuteInBrowser(script)
end)
