-- toJSON() always wraps its argument in a top-level JSON array - stripped
-- before embedding into a JS string (see docs/Architecture.md).
local function toJsonValue(value)
    local json = toJSON(value, true)
    return json:sub(2, -2)
end

--- Deobfuscates and JSON-decodes a CEF->Lua event payload, returning nil
--- (and logging) if it isn't a well-formed table.
-- @param obfuscatedPayload string
-- @return table|nil
local function decodePayload(obfuscatedPayload)
    local jsonPayload = exports.core_ui:uiDeobfuscateFromBrowser(obfuscatedPayload) or obfuscatedPayload
    local payload = fromJSON(jsonPayload)

    if type(payload) ~= "table" then
        return nil
    end
    return payload
end

addEvent(Events.ACCOUNTS_UPSERT, true)
addEventHandler(Events.ACCOUNTS_UPSERT, root, function(obfuscatedPayload)
    local payload = decodePayload(obfuscatedPayload)
    if not payload or type(payload.login) ~= "string" or type(payload.password) ~= "string" or type(payload.rememberPassword) ~= "boolean" then
        outputDebugString("AccountsTransport: received malformed accounts.upsert payload", 2)
        return
    end

    CredentialStore.upsert(payload.login, payload.password, payload.rememberPassword)
end)

addEvent(Events.ACCOUNTS_TOUCH, true)
addEventHandler(Events.ACCOUNTS_TOUCH, root, function(obfuscatedPayload)
    local payload = decodePayload(obfuscatedPayload)
    if not payload or type(payload.login) ~= "string" then
        outputDebugString("AccountsTransport: received malformed accounts.touch payload", 2)
        return
    end

    CredentialStore.touch(payload.login)
end)

addEvent(Events.ACCOUNTS_REMOVE, true)
addEventHandler(Events.ACCOUNTS_REMOVE, root, function(obfuscatedPayload)
    local payload = decodePayload(obfuscatedPayload)
    if not payload or type(payload.login) ~= "string" then
        outputDebugString("AccountsTransport: received malformed accounts.remove payload", 2)
        return
    end

    CredentialStore.remove(payload.login)
end)

addEvent(Events.ACCOUNTS_LIST, true)
addEventHandler(Events.ACCOUNTS_LIST, root, function()
    local response = { accounts = CredentialStore.list() }

    local obfuscated = exports.core_ui:uiObfuscateForBrowser(toJsonValue(response))
    local script = string.format(
        "window.__mtaAccountsLoaded && window.__mtaAccountsLoaded(%s)",
        ("'%s'"):format(tostring(obfuscated):gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", ""))
    )
    exports.core_ui:uiExecuteInBrowser(script)
end)
