-- Server-side integrity gate for the CEF frontend bundle.
--
-- The UI build (packages/[project]/scripts/build-ui.mjs) writes
-- client/html/integrity.json: a SHA-256 for every shipped .js asset and the
-- index.html. On resource start this script re-hashes those files on disk and
-- compares. A mismatch means the obfuscated bundle was swapped/edited after the
-- build - we log loudly and (by default) block the UI from opening.
--
-- This is the trust anchor the browser-side self-checksum can't be: it runs on
-- the server, which the player's machine can't touch.

UiIntegrity = UiIntegrity or {}

local MANIFEST_PATH = "client/html/integrity.json"
-- when true a failed check hard-blocks uiOpen; when false it only logs
local BLOCK_ON_FAILURE = true

local state = {
    checked = false,
    ok = false,
    failures = {},
}

local function logInfo(msg)
    if Logger and Logger.info then Logger.info("core_ui", msg) else outputServerLog("[core_ui] " .. msg) end
end
local function logError(msg)
    if Logger and Logger.error then Logger.error("core_ui", msg) else outputServerLog("[core_ui] " .. msg) end
end

local function readAll(path)
    local f = fileExists(path) and fileOpen(path, true) or nil -- read-only
    if not f then return nil end
    local size = fileGetSize(f)
    local data = size > 0 and fileRead(f, size) or ""
    fileClose(f)
    return data
end

local function verify()
    state.checked = true
    state.failures = {}

    local raw = readAll(MANIFEST_PATH)
    if not raw then
        state.ok = false
        table.insert(state.failures, MANIFEST_PATH .. " missing (build without integrity manifest?)")
        return
    end

    local manifest = fromJSON(raw)
    if type(manifest) ~= "table" or type(manifest.files) ~= "table" then
        state.ok = false
        table.insert(state.failures, MANIFEST_PATH .. " is not valid JSON")
        return
    end

    local algo = manifest.algo or "sha256"
    for relPath, expected in pairs(manifest.files) do
        local full = "client/html/" .. relPath
        local contents = readAll(full)
        if not contents then
            table.insert(state.failures, relPath .. " missing on disk")
        else
            local actual = hash(algo, contents)
            if actual ~= expected then
                table.insert(state.failures, relPath ..
                    " hash mismatch (expected " .. string.sub(expected, 1, 12) ..
                    "…, got " .. string.sub(actual, 1, 12) .. "…)")
            end
        end
    end

    state.ok = (#state.failures == 0)
end

local function manifestCount()
    local raw = readAll(MANIFEST_PATH)
    local m = raw and fromJSON(raw)
    if type(m) == "table" and type(m.files) == "table" then
        local n = 0
        for _ in pairs(m.files) do n = n + 1 end
        return n
    end
    return 0
end

addEventHandler("onResourceStart", resourceRoot, function()
    verify()
    if state.ok then
        logInfo("UI integrity OK (" .. tostring(manifestCount()) .. " files verified)")
    else
        logError("UI INTEGRITY FAILURE:\n  - " .. table.concat(state.failures, "\n  - "))
        if BLOCK_ON_FAILURE then
            logError("UI is BLOCKED until the bundle matches the manifest (rebuild with build-ui.mjs).")
        end
    end
end)

--- Other server code (BrowserManager's open path) should gate on this.
--- @return boolean ok, table failures
function uiIntegrityStatus()
    if not state.checked then verify() end
    return state.ok, state.failures
end

--- Hard gate: returns true only if the UI is safe to open.
--- @return boolean
function uiIntegrityAllowsOpen()
    if not state.checked then verify() end
    if state.ok then return true end
    return not BLOCK_ON_FAILURE
end

-- Client asks before it calls loadBrowserURL. We answer allow/deny.
addEvent(Events.UI_INTEGRITY_QUERY, true)
addEventHandler(Events.UI_INTEGRITY_QUERY, root, function()
    local allowed = uiIntegrityAllowsOpen()
    if not allowed then
        outputServerLog(("[core_ui] Denied UI load for %s - bundle failed integrity check."):format(
            (isElement(client) and getPlayerName(client)) or "?"))
    end
    triggerClientEvent(client, Events.UI_INTEGRITY_RESULT, root, allowed, state.failures or {})
end)

-- Ops: `/uiintegrity` re-runs the check and prints the result to the caller.
addCommandHandler("uiintegrity", function(player)
    verify()
    local target = isElement(player) and player or nil
    local say = function(m)
        if target then outputChatBox("[core_ui] " .. m, target) else outputServerLog("[core_ui] " .. m) end
    end
    if state.ok then
        say(("integrity OK - %d files match the manifest"):format(manifestCount()))
    else
        say("INTEGRITY FAILURE:")
        for _, f in ipairs(state.failures) do say("  - " .. f) end
    end
end, false, false)
