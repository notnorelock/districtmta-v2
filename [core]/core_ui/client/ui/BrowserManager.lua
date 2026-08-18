-- Owns the single long-lived CEF browser instance; other resources use
-- UI.open/close/isOpen rather than calling createBrowser themselves.
-- createBrowser() only produces an off-screen texture - it does not render
-- to the screen, so this file manually draws it via dxDrawImage each frame
-- and forwards cursor/click/focus input into it manually too.

UI = UI or {}

local browser = nil
local openWindows = {}
local browserReady = false
local lastCursorPos = { 0, 0 }
local queuedMessages = {}
local browserFocused = false
local screenWidth, screenHeight = 0, 0

local UI_URL = "http://mta/local/client/html/index.html"

local function flushQueuedMessages()
    if not browserReady or not browser then
        return
    end

    for _, message in ipairs(queuedMessages) do
        executeBrowserJavascript(browser, message)
    end
    queuedMessages = {}
end

local function sendToBrowser(script)
    if browserReady and browser then
        executeBrowserJavascript(browser, script)
    else
        queuedMessages[#queuedMessages + 1] = script
    end
end

--- @return boolean true if any currently-open blocking window wants cursor/input capture
local function anyBlockingWindowOpen()
    for _, entry in pairs(openWindows) do
        if entry.blocking then
            return true
        end
    end
    return false
end

local function updateInputState()
    local anyOpen = anyBlockingWindowOpen()
    showCursor(anyOpen)
    guiSetInputEnabled(anyOpen)

    toggleControl("fire", not anyOpen)
    toggleControl("next_weapon", not anyOpen)
    toggleControl("previous_weapon", not anyOpen)

    if browser and isElement(browser) and anyOpen ~= browserFocused then
        browserFocused = anyOpen
        focusBrowser(anyOpen and browser or nil)
    end

    local openList = {}
    for windowName in pairs(openWindows) do
        openList[#openList + 1] = windowName
    end
    outputDebugString(string.format(
        "[DEBUG] [BrowserManager] updateInputState: anyOpen=%s openWindows={%s}",
        tostring(anyOpen), table.concat(openList, ", ")
    ))
end

--- Opens a named UI window/overlay. Lua only tracks that it's open, for
--- input/cursor purposes, and notifies the browser via the ui.open push channel.
-- @param windowName string
-- @param blocking boolean|nil defaults to true; false lets a window sit on top of gameplay without capturing input
UI.open = function(windowName, blocking)
    outputDebugString("[DEBUG] [BrowserManager] UI.open called: " .. tostring(windowName))

    if openWindows[windowName] then
        return
    end

    openWindows[windowName] = { blocking = blocking ~= false }
    updateInputState()

    local obfuscated = obfuscatePayload(toJsonValue(windowName), SessionKeyState.key)
    sendToBrowser(string.format(
        "window.__mtaPushEvent && window.__mtaPushEvent(%s, %s)",
        toJsonValue(Events.PUSH_UI_OPEN),
        jsStringLiteral(obfuscated)
    ))
end

--- Closes a named UI window/overlay.
-- @param windowName string
UI.close = function(windowName)
    outputDebugString("[DEBUG] [BrowserManager] UI.close called: " .. tostring(windowName))

    if not openWindows[windowName] then
        outputDebugString("[DEBUG] [BrowserManager] UI.close: window was not open, no-op: " .. tostring(windowName))
        return
    end

    openWindows[windowName] = nil
    updateInputState()

    local obfuscated = obfuscatePayload(toJsonValue(windowName), SessionKeyState.key)
    sendToBrowser(string.format(
        "window.__mtaPushEvent && window.__mtaPushEvent(%s, %s)",
        toJsonValue(Events.PUSH_UI_CLOSE),
        jsStringLiteral(obfuscated)
    ))
end

--- Pushes an arbitrary named event with a plain-data payload into the
--- browser's window.__mtaPushEvent entry point, for callers with no "window" concept.
-- @param eventName string
-- @param data any plain-data value, JSON-serializable
UI.pushEvent = function(eventName, data)
    local obfuscated = obfuscatePayload(toJsonValue(data), SessionKeyState.key)
    sendToBrowser(string.format(
        "window.__mtaPushEvent && window.__mtaPushEvent(%s, %s)",
        toJsonValue(eventName),
        jsStringLiteral(obfuscated)
    ))
end

--- @param windowName string
-- @return boolean
UI.isOpen = function(windowName)
    return openWindows[windowName] ~= nil
end

--- @return boolean whether the browser element exists and finished loading its document
UI.isReady = function()
    return browserReady
end

--- Internal: exposed so Transport.lua can push events into the browser.
-- @param script string
UI.executeInBrowser = function(script)
    sendToBrowser(script)
end

--- @return userdata|nil the underlying browser element, for Transport.lua only
UI.getBrowser = function()
    return browser
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    screenWidth, screenHeight = guiGetScreenSize()
    browser = createBrowser(screenWidth, screenHeight, true, true)
end)

addEventHandler("onClientBrowserCreated", root, function()
    if source ~= browser then
        return
    end
    loadBrowserURL(browser, UI_URL)
end)

addEventHandler("onClientBrowserDocumentReady", root, function()
    if source ~= browser then
        return
    end
    browserReady = true
    flushQueuedMessages()
end)

addEventHandler("onClientRender", root, function()
    if not browser or not isElement(browser) then
        return
    end

    dxDrawImage(0, 0, screenWidth, screenHeight, browser, 0, 0, 0, tocolor(255, 255, 255, 255), false)

    if not isCursorShowing() then
        return
    end

    local cursorX, cursorY = getCursorPosition()
    if not cursorX or not cursorY then
        return
    end

    cursorX, cursorY = cursorX * screenWidth, cursorY * screenHeight

    if cursorX ~= lastCursorPos[1] or cursorY ~= lastCursorPos[2] then
        lastCursorPos = { cursorX, cursorY }
        injectBrowserMouseMove(browser, cursorX, cursorY)
    end
end)

addEventHandler("onClientClick", root, function(button, state)
    if not browserFocused or not browser or not isElement(browser) then
        return
    end

    if button ~= "left" and button ~= "middle" and button ~= "right" then
        return
    end

    if state == "down" then
        injectBrowserMouseDown(browser, button)
    elseif state == "up" then
        injectBrowserMouseUp(browser, button)
    end
end)

addEventHandler("onClientKey", root, function(key, state)
    if not state or not browserFocused or not browser or not isElement(browser) then
        return
    end

    if key == "mouse_wheel_down" then
        injectBrowserMouseWheel(browser, -40, 0)
    elseif key == "mouse_wheel_up" then
        injectBrowserMouseWheel(browser, 40, 0)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if browser and isElement(browser) then
        destroyElement(browser)
    end
    browser = nil
    browserReady = false
    browserFocused = false
    openWindows = {}
end)

-- CEF devtools for debugging the frontend in-game: /browserdebug
addCommandHandler("browserdebug", function()
    if not browser or not isElement(browser) then
        outputChatBox("browserdebug: browser not created yet")
        return
    end

    setDevelopmentMode(true, true)
    toggleBrowserDevTools(browser, true)
end)

-- Flat exported wrappers - MTA exports only resolve bare global functions, not dotted paths like UI.open.
function uiOpen(windowName, blocking) UI.open(windowName, blocking) end
function uiClose(windowName) UI.close(windowName) end
function uiIsOpen(windowName) return UI.isOpen(windowName) end
function uiIsReady() return UI.isReady() end

function uiExecuteInBrowser(script) UI.executeInBrowser(script) end
function uiPushEvent(eventName, data) UI.pushEvent(eventName, data) end

-- Exported so other client-side resources can obfuscate/deobfuscate payloads with the current session key.
function uiObfuscateForBrowser(plaintext) return obfuscatePayload(plaintext, SessionKeyState.key) end
function uiDeobfuscateFromBrowser(encoded) return deobfuscatePayload(encoded, SessionKeyState.key) end
