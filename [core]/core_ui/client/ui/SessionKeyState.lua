-- Shared session-key state across this resource's separate Lua chunks -
-- see docs/UiBridge.md's "Payload obfuscation" section.
function pushSessionKeyToBrowser()
    if not SessionKeyState.key then
        return
    end
    UI.executeInBrowser(string.format(
        "window.__mtaSessionKey = %s",
        jsStringLiteral(SessionKeyState.key)
    ))
end

-- Mirrors core_ui/server/SessionKeyDelivery.lua's sessionKeyEventName -
-- see that file's module comment for why the event name is derived from
-- getPlayerSerial rather than a fixed literal.
local sessionKeyEventName = sha256(getPlayerSerial())
addEvent(sessionKeyEventName, true)
addEventHandler(sessionKeyEventName, root, function(key)
    SessionKeyState.key = key
    pushSessionKeyToBrowser()
end)

SessionKeyState = SessionKeyState or { key = nil }