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

addEvent("sessionKey", true)
addEventHandler("sessionKey", root, function(key)
    SessionKeyState.key = key
    pushSessionKeyToBrowser()
end)

SessionKeyState = SessionKeyState or { key = nil }