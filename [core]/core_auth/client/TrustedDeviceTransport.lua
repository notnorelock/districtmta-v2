-- toJSON() always wraps its argument in a top-level JSON array - stripped
-- before embedding into a JS string (see docs/Architecture.md).
local function toJsonValue(value)
    local json = toJSON(value, true)
    return json:sub(2, -2)
end

addEvent(Events.TRUSTED_DEVICE_SAVE, true)
addEventHandler(Events.TRUSTED_DEVICE_SAVE, root, function(obfuscatedPayload)
    local jsonPayload = exports.core_ui:uiDeobfuscateFromBrowser(obfuscatedPayload) or obfuscatedPayload
    local payload = fromJSON(jsonPayload)

    if type(payload) ~= "table" or type(payload.token) ~= "string" then
        outputDebugString("TrustedDeviceTransport: received malformed trustedDevice.save payload", 2)
        return
    end

    TrustedDeviceStore.save(payload.token)
end)

addEvent(Events.TRUSTED_DEVICE_CLEAR, true)
addEventHandler(Events.TRUSTED_DEVICE_CLEAR, root, function()
    TrustedDeviceStore.clear()
end)

addEvent(Events.TRUSTED_DEVICE_LOAD, true)
addEventHandler(Events.TRUSTED_DEVICE_LOAD, root, function()
    local token = TrustedDeviceStore.load()
    local response = { token = token }

    local obfuscated = exports.core_ui:uiObfuscateForBrowser(toJsonValue(response))
    local script = string.format(
        "window.__mtaTrustedDeviceLoaded && window.__mtaTrustedDeviceLoaded(%s)",
        ("'%s'"):format(tostring(obfuscated):gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", ""))
    )
    exports.core_ui:uiExecuteInBrowser(script)
end)
