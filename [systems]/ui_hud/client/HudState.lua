HUD = HUD or {}

local function isResourceAvailable(resourceName)
    local resource = getResourceFromName(resourceName)
    if not resource then
        return false
    end

    local state = getResourceState(resource)
    return state == "running" or state == "loaded"
end

local HUD_OVERLAY = "hud"
local WATERMARK_OVERLAY = "watermark"
local GTA_COMPONENTS = { "radar", "area_name", "vehicle_name", "armour", "breath", "clock", "health", "money", "weapon", "wanted", "radio", "ammo" }
local UPDATE_INTERVAL_MS = 2500
local MIN_PUSH_INTERVAL_MS = 250
local PLACEHOLDER_HUNGER = 100
local PLACEHOLDER_THIRST = 100
local VOICE_MODE_LEVEL = {
    [Enums.VoiceMode.WHISPER] = 33,
    [Enums.VoiceMode.TALK] = 66,
    [Enums.VoiceMode.SHOUT] = 100,
}
local DEFAULT_VOICE_LEVEL = VOICE_MODE_LEVEL[Enums.VoiceMode.TALK]

local active = false
local lastHealth = 0
local lastOxygenPercent = 100
local lastInWater = false
local lastVoiceActive = false
local lastVoiceLevel = DEFAULT_VOICE_LEVEL
local lastSpeedoVisible = false
local lastUpdateTick = 0
local lastPushTick = 0
local pendingChange = false

local function getPedMaxOxygenLevel(ped)
    local underwater_stamina = getPedStat(ped, 225)
    local stamina = getPedStat(ped, 22)
    local maxoxygen = 1000 + underwater_stamina * 1.5 + stamina * 1.5
    return maxoxygen
end

local function oxygenPercent()
    if not isElementInWater(localPlayer) then
        return 100
    end

    local max = getPedMaxOxygenLevel(localPlayer)
    if not max or max <= 0 then return 100 end
    return math.floor(math.min(100, (getPedOxygenLevel(localPlayer) / max) * 100))
end

local function voiceState()
    if not isResourceAvailable("gm_voice") then
        return false, DEFAULT_VOICE_LEVEL
    end

    local isVoiceActive = exports.gm_voice:voiceStateIsTalking(localPlayer) == true
    local mode = exports.gm_voice:voiceStateGetMode(localPlayer)
    return isVoiceActive, VOICE_MODE_LEVEL[mode] or DEFAULT_VOICE_LEVEL
end

local function resetTrackedState()
    lastUpdateTick = getTickCount()
    lastPushTick = 0
    pendingChange = false
    lastHealth = 0
    lastOxygenPercent = 100
    lastInWater = false
    lastVoiceActive = false
    lastVoiceLevel = DEFAULT_VOICE_LEVEL
    lastSpeedoVisible = false
end

local function trackStateChanged()
    local health = isPedDead(localPlayer) and 0 or math.floor(getElementHealth(localPlayer))
    local oxygenPct = oxygenPercent()
    local inWater = isElementInWater(localPlayer)
    local voiceActive, voiceLevel = voiceState()
    local speedoVisible = isSpeedoVisible()

    if health == lastHealth and oxygenPct == lastOxygenPercent and inWater == lastInWater
        and voiceActive == lastVoiceActive and voiceLevel == lastVoiceLevel
        and speedoVisible == lastSpeedoVisible then
        return false
    end

    lastHealth = health
    lastOxygenPercent = oxygenPct
    lastInWater = inWater
    lastVoiceActive = voiceActive
    lastVoiceLevel = voiceLevel
    lastSpeedoVisible = speedoVisible
    return true
end

HUD.pushHudState = function(force)
    if not active then return end

    if force then
        lastHealth = isPedDead(localPlayer) and 0 or math.floor(getElementHealth(localPlayer))
        lastOxygenPercent = oxygenPercent()
        lastInWater = isElementInWater(localPlayer)
        lastVoiceActive, lastVoiceLevel = voiceState()
        lastSpeedoVisible = isSpeedoVisible()
        lastUpdateTick = getTickCount()
    end

    local radarX, radarY, radarW, radarH = getRadarPosition()

    exports.core_ui:uiPushEvent(Events.PUSH_HUD_UPDATED, {
        health = lastHealth,
        hunger = PLACEHOLDER_HUNGER,
        thirst = PLACEHOLDER_THIRST,
        oxygen = lastOxygenPercent,
        drowning = lastInWater or lastOxygenPercent < 100,
        voiceActive = lastVoiceActive,
        voiceLevel = lastVoiceLevel,
        radarVisible = isRadarVisible(),
        radarPosition = radarX and { x = radarX, y = radarY, w = radarW, h = radarH } or false,
        speedoVisible = lastSpeedoVisible,
        speedoHeight = getSpeedoHeight(),
    })
end

local userPreferenceHidden = false
local temporarilyHidden = false

-- Guarded on `active` - without this, a preference/temporary-hide call
-- arriving BEFORE the player has ever spawned (e.g. gm_settings' own
-- resyncElementData fires SETTINGS_APPLY on PLAYER_ACCOUNT_RESOLVED,
-- which happens on login, well before spawn - the player is still on
-- the spawn-select screen) would call uiShowOverlay(HUD_OVERLAY)
-- unconditionally and show health/hunger/thirst icons over a screen
-- that has no HUD concept at all. HUD.start() is the only thing allowed
-- to turn the HUD on for the first time each life; this only ever
-- adjusts visibility for an already-started HUD.
local function applyVisibility()
    if not active then
        return
    end

    local visible = not (userPreferenceHidden or temporarilyHidden)
    if visible then
        exports.core_ui:uiShowOverlay(HUD_OVERLAY)
    else
        exports.core_ui:uiHideOverlay(HUD_OVERLAY)
    end
    setRadarVisible(visible)
    setSpeedoVisible(visible)
end

HUD.start = function()
    if not active then
        for _, v in ipairs(GTA_COMPONENTS) do
            setPlayerHudComponentVisible(v, false)
        end

        active = true
        resetTrackedState()
        HUD.pushHudState(true)
    end

    exports.core_ui:uiShowOverlay(WATERMARK_OVERLAY)
    applyVisibility()
end

addEventHandler("onClientPreRender", root, function()
    if not active then return end

    if trackStateChanged() then
        pendingChange = true
    end

    local now = getTickCount()
    if pendingChange and now - lastPushTick >= MIN_PUSH_INTERVAL_MS then
        pendingChange = false
        lastPushTick = now
        lastUpdateTick = now
        HUD.pushHudState()
    elseif now - lastUpdateTick >= UPDATE_INTERVAL_MS then
        lastPushTick = now
        lastUpdateTick = now
        HUD.pushHudState()
    end
end)

addEventHandler("onClientPlayerSpawn", localPlayer, HUD.start)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        exports.core_ui:uiHideOverlay(HUD_OVERLAY)
        exports.core_ui:uiHideOverlay(WATERMARK_OVERLAY)
    end
end)

local function restoreUserPreferenceFromSettings()
    if not isResourceAvailable("gm_settings") then
        return
    end
    local ok, enabled = pcall(function()
        return exports.gm_settings:settingsStateIsEnabled("hud_disabled")
    end)
    if ok then
        userPreferenceHidden = enabled == true
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    restoreUserPreferenceFromSettings()

    if getElementData(localPlayer, ElementData.Player.SPAWNED) == true then
        HUD.start()
    end
end)

setHUDVisible = function(state)
    temporarilyHidden = not state
    applyVisibility()
end

function setHUDUserPreference(hidden)
    userPreferenceHidden = hidden == true
    applyVisibility()
end