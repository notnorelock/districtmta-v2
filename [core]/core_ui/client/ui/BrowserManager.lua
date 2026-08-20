-- Owns the single long-lived CEF browser instance; other resources use
-- UI.open/close/isOpen rather than calling createBrowser themselves.
-- createBrowser() only produces an off-screen texture - it does not render
-- to the screen, so this file manually draws it via dxDrawImage each frame
-- and forwards cursor/click/focus input into it manually too.

UI = UI or {}

local browser = nil
local openWindows = {}
local visibleOverlays = {}
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

-- Overlays are a separate registry from openWindows/UI.open - never touch
-- showCursor/guiSetInputEnabled/focusBrowser, so any number of them can be
-- visible at once alongside a blocking window without fighting over
-- input focus. Unlike windows, the browser side has no matching "close
-- yourself" affordance - only script (Lua) code shows/hides an overlay,
-- by design (see Events.PUSH_OVERLAY_SHOW's module comment). HUD is the
-- first overlay; anything gameplay-permanent (killfeed, interaction
-- prompts, a minimap) should reuse this instead of a new one-off channel.

--- Shows a named overlay in the browser. No-ops if already visible.
-- @param overlayName string
UI.showOverlay = function(overlayName)
    if visibleOverlays[overlayName] then
        return
    end
    visibleOverlays[overlayName] = true

    local obfuscated = obfuscatePayload(toJsonValue(overlayName), SessionKeyState.key)
    sendToBrowser(string.format(
        "window.__mtaPushEvent && window.__mtaPushEvent(%s, %s)",
        toJsonValue(Events.PUSH_OVERLAY_SHOW),
        jsStringLiteral(obfuscated)
    ))
end

--- Hides a named overlay in the browser. No-ops if not visible.
-- @param overlayName string
UI.hideOverlay = function(overlayName)
    if not visibleOverlays[overlayName] then
        return
    end
    visibleOverlays[overlayName] = nil

    local obfuscated = obfuscatePayload(toJsonValue(overlayName), SessionKeyState.key)
    sendToBrowser(string.format(
        "window.__mtaPushEvent && window.__mtaPushEvent(%s, %s)",
        toJsonValue(Events.PUSH_OVERLAY_HIDE),
        jsStringLiteral(obfuscated)
    ))
end

--- @param overlayName string
-- @return boolean
UI.isOverlayVisible = function(overlayName)
    return visibleOverlays[overlayName] ~= nil
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

--- Focuses/unfocuses the browser and toggles cursor+GUI input on demand,
--- independent of UI.open/openWindows - for a caller that wants cursor
--- input into the browser WITHOUT going through the open/blocking window
--- flow (e.g. gm_scoreboard: TAB alone shows an overlay with no cursor,
--- only a held right-click additionally wants pointer input). Does NOT
--- touch toggleControl("fire"/etc.) or openWindows bookkeeping - callers
--- needing to also block movement do that themselves (toggleAllControls),
--- same as gm_blackout already does independently of this file.
--- Must be balanced by the caller (focus(true) then eventually focus(false));
--- does not intersect with a currently-open blocking window's own state -
--- calling this while a blocking UI.open window is open, or leaving it
--- engaged when one opens, can fight over focusBrowser/showCursor. Callers
--- are expected to only use this when they know no blocking window is open.
-- @param wantsFocus boolean
UI.focusBrowser = function(wantsFocus)
    if not browser or not isElement(browser) then
        return
    end

    showCursor(wantsFocus)
    guiSetInputEnabled(wantsFocus)

    if wantsFocus ~= browserFocused then
        browserFocused = wantsFocus
        focusBrowser(wantsFocus and browser or nil)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    screenWidth, screenHeight = guiGetScreenSize()
    browser = createBrowser(screenWidth, screenHeight, true, true)

    setBlurShaderEnabled(true, browser)
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
        setBlurShaderEnabled(false, nil)
        destroyElement(browser)
    end
    browser = nil
    browserReady = false
    browserFocused = false
    openWindows = {}
    visibleOverlays = {}
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

function uiShowOverlay(overlayName) UI.showOverlay(overlayName) end
function uiHideOverlay(overlayName) UI.hideOverlay(overlayName) end
function uiIsOverlayVisible(overlayName) return UI.isOverlayVisible(overlayName) end

function uiExecuteInBrowser(script) UI.executeInBrowser(script) end
function uiPushEvent(eventName, data) UI.pushEvent(eventName, data) end
function uiFocusBrowser(wantsFocus) UI.focusBrowser(wantsFocus) end

-- Exported so other client-side resources can obfuscate/deobfuscate payloads with the current session key.
function uiObfuscateForBrowser(plaintext) return obfuscatePayload(plaintext, SessionKeyState.key) end
function uiDeobfuscateFromBrowser(encoded) return deobfuscatePayload(encoded, SessionKeyState.key) end
