-- Starts every project resource in dependency order (see docs/Architecture.md).
-- The only resource with startup="1" in mtaserver.conf - everything else is
-- started BY this file so relative order never depends on mtaserver.conf's
-- own <resource> line order. Each step waits for onResourceStart before
-- starting the next, since a resource may read proxied globals from an
-- earlier one at its own load time (see every GlobalResources.lua).

-- gm_voice before ui_hud: ui_hud's client (HudState.lua) calls gm_voice's
-- exports (voiceStateIsTalking/voiceStateGetMode) for the local player's
-- voice-mode HUD ring, so gm_voice must exist first. gm_vehicles_interaction
-- before gm_radio: gm_radio's client (RadioState.lua) calls
-- gm_vehicles_interaction's export (vehicleInteractionIsMenuOpen) to skip
-- its own scroll-to-change-station handling while the vehicle interaction
-- radial menu is open, so gm_vehicles_interaction must exist first.
-- gm_vehicles itself has no such dependency from gm_radio (or anything
-- else) and can start anywhere in this tier.

-- markers after core_ui: [custom]/markers' client (marker.lua) calls
-- core_ui's export (getUIFont) to draw its text labels, so core_ui must
-- exist first. models and gm_3dtext have no cross-resource dependency of
-- their own and just need to exist somewhere in the chain so
-- core_bootstrap actually starts them (see the "does not exist" abort
-- check in startNext below) rather than relying on mtaserver.conf's own
-- resource list/order.

-- gm_interactions after core (its GlobalResources.lua proxies
-- Permissions/PlayerService/Logger from it, same as gm_vehicles) and
-- core_ui (its CEF overlay push events go through uiShowOverlay/
-- uiPushEvent) - no dependency on gm_vehicles/gm_vehicles_interaction
-- despite its admin vehicle interactions, since those touch the live
-- vehicle element directly via plain MTA natives rather than calling into
-- either resource.

-- gm_items after gm_interactions: its world-item pickup goes through
-- gm_interactions' generic "object:itemPickup" InteractionRegistry entry
-- (see InteractionRegistry.lua's own module comment on why gm_items can't
-- register that entry itself - a handler function can't cross the
-- resource boundary) - that entry needs to exist before a player could
-- plausibly interact with a dropped item. Also after gm_vehicles: its
-- vehicle-key item type reads ElementData.Vehicle.ID, which gm_vehicles
-- sets on spawn.

-- gm_nametags after core_ui (its client calls getUIFont, same dependency
-- markers has) and after core (its GlobalResources.lua proxies
-- PlayerService/Permissions from it, same as gm_interactions/gm_vehicles) -
-- no gameplay-tier dependency of its own, so it's placed right alongside
-- markers/models/gm_3dtext rather than waiting for the whole gameplay chain.

-- gm_groups after core (its GlobalResources.lua proxies PlayerService/
-- Permissions/Logger/NotificationService from it, and its GroupBridge.lua
-- talks to core/server/GroupService.lua's repository bridge, same as
-- gm_vehicles' own VehicleBridge.lua dependency on core) and after core_ui
-- (its CEF panel/duty indicator go through uiShowOverlay/uiPushEvent, same
-- as gm_interactions) - no dependency on gm_vehicles/gm_items/any other
-- gameplay resource, so it's placed alongside gm_interactions/gm_items
-- rather than at the very end of the chain.
local START_ORDER = { "core_shared", "core", "core_ui", "core_loading", "core_auth", "core_admin", "markers", "models", "gm_3dtext", "gm_nametags", "gm_voice", "gm_vehicles", "gm_vehicles_interaction", "gm_interactions", "gm_items", "gm_groups", "gm_radio", "gm_blackout", "gm_scoreboard", "ui_hud", "gm_settings", "gm_worldmap", "gm_roleplay" }
local START_TIMEOUT_MS = 15000

--- Extra pause after a resource's SERVER-side start before starting the
--- next - onResourceStart says nothing about that resource's CLIENT-side
--- scripts having finished on already-connected clients, so this is a
--- pragmatic buffer (not a guarantee) for a client-side module that reads
--- a proxied global at its own load time.
local STEP_DELAY_MS = 750

local function isRunning(resourceName)
    local resource = getResourceFromName(resourceName)
    return resource ~= nil and getResourceState(resource) == "running"
end

local chainReady = false

--- @return boolean whether every resource in START_ORDER has finished being started by this chain at least once
local function isChainReady()
    return chainReady
end

--- Walks START_ORDER from `index` onward, starting each resource that
--- isn't already running, waiting for each to finish before the next.
-- @param index number
local function startNext(index)
    if index > #START_ORDER then
        chainReady = true
        outputServerLog("[INFO] [core_bootstrap] All project resources started successfully.")
        return
    end

    local resourceName = START_ORDER[index]
    local resource = getResourceFromName(resourceName)

    if not resource then
        outputServerLog(string.format(
            "[ERROR] [core_bootstrap] Resource '%s' does not exist - check it's present under mods/deathmatch/resources. Aborting remaining startup.",
            resourceName
        ))
        return
    end

    if isRunning(resourceName) then
        outputServerLog(string.format("[INFO] [core_bootstrap] '%s' already running, skipping.", resourceName))
        startNext(index + 1)
        return
    end

    outputServerLog(string.format("[INFO] [core_bootstrap] Starting '%s' (%d/%d)...", resourceName, index, #START_ORDER))

    local advanced = false
    local function advance()
        if advanced then
            return
        end
        advanced = true

        outputServerLog(string.format(
            "[INFO] [core_bootstrap] '%s' started, waiting %dms before continuing...",
            resourceName, STEP_DELAY_MS
        ))
        setTimer(function()
            startNext(index + 1)
        end, STEP_DELAY_MS, 1)
    end

    -- onResourceStart must be attached to root, not the resource element itself
    -- (a "resource" element is not a valid attach-to target for addEventHandler).
    local function onStarted(startedResource)
        if startedResource ~= resource then
            return
        end
        removeEventHandler("onResourceStart", root, onStarted)
        advance()
    end
    addEventHandler("onResourceStart", root, onStarted)

    -- Fallback in case onResourceStart never fires (e.g. a script error) - logs and moves on.
    setTimer(function()
        if not advanced then
            outputServerLog(string.format(
                "[WARN] [core_bootstrap] '%s' did not fire onResourceStart within %dms - check its console output for errors. Continuing with the rest of the chain anyway.",
                resourceName, START_TIMEOUT_MS
            ))
            advance()
        end
    end, START_TIMEOUT_MS, 1)

    local ok, err = pcall(startResource, resource)
    if not ok then
        outputServerLog(string.format("[ERROR] [core_bootstrap] startResource('%s') threw: %s", resourceName, tostring(err)))
    end
end

--- Restarts every currently-running resource in START_ORDER, synchronously
--- (restartResource is synchronous, unlike startResource's onResourceStart wait).
local function restartRunningChain()
    chainReady = false
    for _, resourceName in ipairs(START_ORDER) do
        if isRunning(resourceName) then
            local resource = getResourceFromName(resourceName)
            outputServerLog(string.format("[INFO] [core_bootstrap] Restarting '%s'...", resourceName))

            local ok, err = pcall(restartResource, resource)
            if not ok then
                outputServerLog(string.format("[ERROR] [core_bootstrap] restartResource('%s') threw: %s", resourceName, tostring(err)))
            end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    startNext(1)
end)

-- MTA has no separate "restart" event - `restart core_bootstrap` is just
-- stop+start of this resource, so the actual chain restart happens here, not onResourceStart.
addEventHandler("onResourceStop", resourceRoot, function()
    restartRunningChain()
end)

-- Flat exported wrapper - core_loading/server/LoadingGate.lua polls this.
function bootstrapIsChainReady()
    return isChainReady()
end
