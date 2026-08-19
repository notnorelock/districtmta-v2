HUD = HUD or {}

local HUD_OVERLAY = "hud"
local UPDATE_INTERVAL_MS = 1500
local PLACEHOLDER_HUNGER = 100
local PLACEHOLDER_THIRST = 100

local active = false
local lastHealth = 0
local lastUpdateTick = 0

local function resetTrackedState()
    lastUpdateTick = getTickCount()
    lastHealth = 0
end

local function trackStateChanged()
    local health = isPedDead(localPlayer) and 0 or math.floor(getElementHealth(localPlayer))

    if health == lastHealth then
        return false
    end

    lastHealth = health
    return true
end

HUD.pushHudState = function(force)
    if not active then return end

    if force then
        lastHealth = isPedDead(localPlayer) and 0 or math.floor(getElementHealth(localPlayer))
        lastUpdateTick = getTickCount()
    end

    exports.core_ui:uiPushEvent(Events.PUSH_HUD_UPDATED, {
        health = lastHealth,
        hunger = PLACEHOLDER_HUNGER,
        thirst = PLACEHOLDER_THIRST,
        voiceActive = false,
    })
end

HUD.start = function()
    exports.core_ui:uiShowOverlay(HUD_OVERLAY)
    if active then return end

    active = true
    resetTrackedState()
    HUD.pushHudState(true)
end

HUD.stop = function()
    if not active then return end

    exports.core_ui:uiHideOverlay(HUD_OVERLAY)
    active = false
end

addEventHandler("onClientPreRender", root, function()
    if not active then return end

    if trackStateChanged() then
        HUD.pushHudState(true)
    elseif getTickCount() - lastUpdateTick >= UPDATE_INTERVAL_MS then
        HUD.pushHudState()
    end
end)

addEventHandler("onClientPlayerSpawn", localPlayer, HUD.start)
addEventHandler("onClientResourceStop", resourceRoot, HUD.stop)

addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, ElementData.Player.SPAWNED) == true then
        HUD.start()
    end
end)
