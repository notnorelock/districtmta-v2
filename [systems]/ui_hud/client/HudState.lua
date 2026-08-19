HUD = HUD or {}

local HUD_OVERLAY = "hud"
local GTA_COMPONENTS = { "radar", "area_name", "vehicle_name", "armour", "breath", "clock", "health", "money", "weapon", "wanted", "radio", "ammo" }
local UPDATE_INTERVAL_MS = 2500
local PLACEHOLDER_HUNGER = 100
local PLACEHOLDER_THIRST = 100

local active = false
local lastHealth = 0
local lastOxygenPercent = 100
local lastInWater = false
local lastUpdateTick = 0

local function getPedMaxOxygenLevel(ped)
    local underwater_stamina = getPedStat(ped, 225)
    local stamina = getPedStat(ped, 22)
    local maxoxygen = 1000 + underwater_stamina * 1.5 + stamina * 1.5
    return maxoxygen
end

local function oxygenPercent()
    local max = getPedMaxOxygenLevel(localPlayer)
    if not max or max <= 0 then return 100 end
    return math.floor(math.min(100, (getPedOxygenLevel(localPlayer) / max) * 100))
end

local function resetTrackedState()
    lastUpdateTick = getTickCount()
    lastHealth = 0
    lastOxygenPercent = 100
    lastInWater = false
end

local function trackStateChanged()
    local health = isPedDead(localPlayer) and 0 or math.floor(getElementHealth(localPlayer))
    local oxygenPct = oxygenPercent()
    local inWater = isElementInWater(localPlayer)

    if health == lastHealth and oxygenPct == lastOxygenPercent and inWater == lastInWater then
        return false
    end

    lastHealth = health
    lastOxygenPercent = oxygenPct
    lastInWater = inWater
    return true
end

HUD.pushHudState = function(force)
    if not active then return end

    if force then
        lastHealth = isPedDead(localPlayer) and 0 or math.floor(getElementHealth(localPlayer))
        lastOxygenPercent = oxygenPercent()
        lastInWater = isElementInWater(localPlayer)
        lastUpdateTick = getTickCount()
    end

    exports.core_ui:uiPushEvent(Events.PUSH_HUD_UPDATED, {
        health = lastHealth,
        hunger = PLACEHOLDER_HUNGER,
        thirst = PLACEHOLDER_THIRST,
        -- Shows as soon as the ped touches water (isElementInWater), not
        -- only once oxygen actually starts depleting - swimming at the
        -- surface doesn"t drain oxygen, but the player is still "in the
        -- water" and the icon should already be visible by then.
        oxygen = lastOxygenPercent,
        drowning = lastInWater or lastOxygenPercent < 100,
        voiceActive = false,
    })
end

HUD.start = function()
    exports.core_ui:uiShowOverlay(HUD_OVERLAY)
    if active then return end

    for _, v in ipairs(GTA_COMPONENTS) do
        if isPlayerHudComponentVisible(v) then
            setPlayerHudComponentVisible(v, not isPlayerHudComponentVisible(v))
        end
    end

    active = true
    resetTrackedState()
    HUD.pushHudState(true)
end

HUD.stop = function()
    if not active then return end

    exports.core_ui:uiHideOverlay(HUD_OVERLAY)

    for _, v in ipairs(GTA_COMPONENTS) do
        if not isPlayerHudComponentVisible(v) then
            setPlayerHudComponentVisible(v, not isPlayerHudComponentVisible(v))
        end
    end

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
