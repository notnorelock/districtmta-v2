HUD = HUD or {}

-- Same isResourceAvailable helper every GlobalResources.lua in this
-- project defines locally - not shared/exported anywhere, so duplicated
-- here rather than introducing a new shared module for one function.
local function isResourceAvailable(resourceName)
    local resource = getResourceFromName(resourceName)
    if not resource then
        return false
    end

    local state = getResourceState(resource)
    return state == "running" or state == "loaded"
end

local HUD_OVERLAY = "hud"
-- Separate overlay key from HUD_OVERLAY on purpose - toggled alongside it
-- here (same spawn/despawn trigger) but independently, so a future
-- "hide HUD" toggle that only touches HUD_OVERLAY doesn't take the
-- watermark down with it.
local WATERMARK_OVERLAY = "watermark"
local GTA_COMPONENTS = { "radar", "area_name", "vehicle_name", "armour", "breath", "clock", "health", "money", "weapon", "wanted", "radio", "ammo" }
local UPDATE_INTERVAL_MS = 2500
-- Hard cap on how often a changed-state push can actually go out, even
-- while health/oxygen/etc. keep changing every single frame (natural
-- regen ticks up/down gradually rather than snapping, so trackStateChanged()
-- can legitimately return true on many consecutive frames in a row while
-- healing/drowning - each one IS a real change, but pushing every frame is
-- still far more often than the HUD (or /browserdebug's console) needs).
local MIN_PUSH_INTERVAL_MS = 250
local PLACEHOLDER_HUNGER = 100
local PLACEHOLDER_THIRST = 100

-- Voice fill level per talk mode (gm_voice's Enums.VoiceMode) - read
-- through gm_voice's own exports (voiceStateIsTalking/voiceStateGetMode,
-- see below) rather than ElementData.Player.VOICE/VOICE_MODE directly, so
-- this stays correct if gm_voice ever changes how it tracks talk state
-- internally. 3 discrete levels instead of a smooth 0-100 so the ring
-- visibly steps whisper -> talk -> shout rather than reading as one
-- continuous "volume" bar. voiceLevel reflects the CURRENT MODE at all
-- times (not just while actively talking) - it's "what mode am I set to",
-- separate from voiceActive ("am I transmitting right now"), which only
-- drives the icon's glow (see HudBar.tsx).
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
-- ui_hud's own native SpeedoComponent visibility (isSpeedoVisible is
-- Bootstrap.lua's own global, same resource) - lets the CEF HUD stack
-- (HudBar/DutyIndicator/LicenseExamHud) shift above the dial exactly
-- while it's showing, same role radarVisible/radarPosition already play
-- for VoiceIndicator.tsx's own dock position.
local lastSpeedoVisible = false
local lastUpdateTick = 0
-- Tick of the last actual uiPushEvent (not the last trackStateChanged()
-- detection) - see MIN_PUSH_INTERVAL_MS's own comment.
local lastPushTick = 0
-- True once trackStateChanged() has seen a change that hasn't made it out
-- in a push yet, because MIN_PUSH_INTERVAL_MS hasn't elapsed - the next
-- push (whenever it happens) still carries it, nothing is lost, it's just
-- not sent on every single frame it was detected on.
local pendingChange = false

local function getPedMaxOxygenLevel(ped)
    local underwater_stamina = getPedStat(ped, 225)
    local stamina = getPedStat(ped, 22)
    local maxoxygen = 1000 + underwater_stamina * 1.5 + stamina * 1.5
    return maxoxygen
end

-- Only meaningful while actually in water - out of water, MTA regenerates
-- oxygen gradually rather than snapping it back to max, so reading the
-- real level here would flicker between e.g. 99/100 frame to frame
-- (isElementInWater is a clean boolean, no such regen curve to flicker
-- against) and spam trackStateChanged()/PUSH_HUD_UPDATED every frame for
-- no visible reason - the HUD only ever shows this while drowning is true
-- anyway (see pushHudState's own drowning field), so a flickering value
-- the player was never going to see was never worth reading in the first
-- place.
local function oxygenPercent()
    if not isElementInWater(localPlayer) then
        return 100
    end

    local max = getPedMaxOxygenLevel(localPlayer)
    if not max or max <= 0 then return 100 end
    return math.floor(math.min(100, (getPedOxygenLevel(localPlayer) / max) * 100))
end

--- @return boolean, number isVoiceActive, voiceLevel (always reflects the
--         CURRENT mode, regardless of isVoiceActive - see VOICE_MODE_LEVEL's
--         own comment) - false/DEFAULT_VOICE_LEVEL if gm_voice isn't
--         running (its exports simply won't be there yet).
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

    -- getRadarPosition/isRadarVisible are Bootstrap.lua's own globals, same
    -- resource - no exports.ui_hud: needed. x/y/w/h are real screen pixels
    -- (dxDraw, not CSS units), but CEF renders at the same 1:1 screen
    -- resolution, so the frontend (VoiceIndicator.tsx) can use them
    -- directly as px - see RadarComponent.lua's own getPosition().
    local radarX, radarY, radarW, radarH = getRadarPosition()

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
        voiceActive = lastVoiceActive,
        -- 33/66/100 (whisper/talk/shout) while voiceActive - see
        -- VOICE_MODE_LEVEL's own comment. HudIcon renders this as the
        -- ring's fill percentage, same mechanic as health/hunger/thirst.
        voiceLevel = lastVoiceLevel,
        -- Lets VoiceIndicator.tsx dock itself beside the native radar
        -- instead of a fixed CSS position - radarPosition is false (not a
        -- table) whenever the radar component isn't ready yet, same
        -- "false means not ready" convention getRadarPosition() itself uses.
        radarVisible = isRadarVisible(),
        radarPosition = radarX and { x = radarX, y = radarY, w = radarW, h = radarH } or false,
        speedoVisible = lastSpeedoVisible,
        -- Zoom-adjusted px, same "real dxDraw px, CEF renders 1:1"
        -- convention radarPosition's w/h already use - always sent (not
        -- gated behind speedoVisible) so the CEF side has a real number
        -- to animate the offset TO before the field flips true, avoiding
        -- a 0->390 snap on the same frame visibility turns on.
        speedoHeight = getSpeedoHeight(),
    })
end

-- `active` now means ONLY "is the HUD SYSTEM running" (native GTA
-- components turned off, state tracking/pushes live) - it starts once on
-- spawn and STAYS on for the rest of that life, regardless of F11/
-- blackout/the player's own "Ukryj HUD" setting. None of those three
-- ever fully stop the system anymore; they only hide the VISIBLE parts
-- (CEF hud/watermark overlays + the dxDraw radar/speedo components),
-- independently of whether the system underneath is tracking state.
-- This is what lets a relogged player who has "Ukryj HUD" enabled still
-- get GTA_COMPONENTS turned off and state tracking running from the
-- first frame, without the CEF/radar/speedo ever flashing visible first.
local userPreferenceHidden = false
-- Separate from userPreferenceHidden - a TEMPORARY hide (F11's world
-- map, gm_blackout) while the standing preference itself is "visible".
-- The two combine with OR in applyVisibility() below: hidden if EITHER
-- wants it hidden, visible only once BOTH want it visible again.
local temporarilyHidden = false

--- Applies the current combined visibility (userPreferenceHidden OR
--- temporarilyHidden -> hidden) to the CEF hud/watermark overlays and
--- the dxDraw radar/speedo components - called after every point that
--- could change either flag, or after HUD.start() first turns the
--- system on. Never touches `active`/GTA_COMPONENTS/state tracking -
--- those are HUD.start()'s own one-time job for this life.
local function applyVisibility()
    local visible = not (userPreferenceHidden or temporarilyHidden)
    if visible then
        exports.core_ui:uiShowOverlay(HUD_OVERLAY)
        exports.core_ui:uiShowOverlay(WATERMARK_OVERLAY)
    else
        exports.core_ui:uiHideOverlay(HUD_OVERLAY)
        exports.core_ui:uiHideOverlay(WATERMARK_OVERLAY)
    end
    -- Bootstrap.lua's own RadarComponent starts hidden (self.visible =
    -- false) - without this call there would be no radar at all once
    -- `visible` is true, even though GTA_COMPONENTS below already
    -- permanently turns off the native GTA radar this replaces.
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

    applyVisibility()
end

addEventHandler("onClientPreRender", root, function()
    if not active then return end

    -- trackStateChanged() runs every frame regardless (it's what keeps
    -- lastHealth/lastOxygenPercent/etc. current - gradual regen/drowning
    -- can legitimately flip it true on many consecutive frames), but the
    -- resulting uiPushEvent is rate-limited to MIN_PUSH_INTERVAL_MS via
    -- pendingChange below - trackStateChanged()'s own already-written
    -- lastX fields are what the eventual push reads, so no change is ever
    -- lost, it just isn't sent more often than the cap allows.
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

-- Resource stop/start no longer tears the system down via a HUD.stop()
-- that also flips `active` off - a restart mid-life should keep GTA_COMPONENTS
-- off and tracking running exactly as before, just re-showing whatever
-- was already visible (applyVisibility() reads the still-live flags).
addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        exports.core_ui:uiHideOverlay(HUD_OVERLAY)
        exports.core_ui:uiHideOverlay(WATERMARK_OVERLAY)
    end
end)

-- Same "resource might not be running" pcall-wrapped guard every other
-- cross-resource read in this project uses (e.g. voiceState() above,
-- via the isResourceAvailable() already defined at the top of this
-- file) - gm_settings may not have started yet/at all depending on
-- restart order, in which case userPreferenceHidden correctly stays at
-- its false default (HUD visible) rather than erroring.
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
    -- ui_hud restarting on its own (without gm_settings also
    -- restarting) would otherwise reset userPreferenceHidden to its
    -- module-load default (false) and briefly flash the HUD visible for
    -- a player who has "Ukryj HUD" enabled, until the next real
    -- SETTINGS_APPLY push (login or an actual toggle) - restoring it
    -- from gm_settings' own remembered state here closes that gap.
    restoreUserPreferenceFromSettings()

    if getElementData(localPlayer, ElementData.Player.SPAWNED) == true then
        HUD.start()
    end
end)

--- Temporary show/hide around some other full-screen UI (F11's world
--- map, gm_blackout) - never touches the standing userPreferenceHidden,
--- see temporarilyHidden's own comment above. Also never stops the HUD
--- SYSTEM (GTA_COMPONENTS/state tracking) - only the visible parts.
-- @param state boolean true = "I'm done, show it again" (still subject
--        to userPreferenceHidden), false = "hide it while I'm open"
setHUDVisible = function(state)
    temporarilyHidden = not state
    applyVisibility()
end

--- The ONLY setter for userPreferenceHidden - called exclusively by
--- gm_settings' own "Ukryj HUD" toggle. Applies immediately, same
--- combine-with-temporarilyHidden rule as setHUDVisible above.
-- @param hidden boolean
function setHUDUserPreference(hidden)
    userPreferenceHidden = hidden == true
    applyVisibility()
end