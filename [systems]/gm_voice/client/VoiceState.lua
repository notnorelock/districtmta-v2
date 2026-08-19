-- Client-side voice presentation: distance/fade volume falloff, stereo
-- panning toward the speaker's on-screen direction, and pushing the
-- "who's talking nearby" list into the CEF HUD (see the bottom of this
-- file - VoiceIndicator.tsx on the frontend renders it, not dxDraw; dxGUI
-- is reserved for small one-off admin tools, the real HUD lives in CEF).
-- The server (VoiceService.lua) already decided WHO can hear WHOM via
-- setPlayerVoiceBroadcastTo - this file only shapes how an already-audible
-- speaker sounds/looks, it has no authority over broadcast targets or mute
-- state.
VoiceState = VoiceState or {}

local BASE_VOLUME = 1.0
-- Client-side audible-falloff range per speaker's talk mode - separate
-- from VoiceService.lua's server-side broadcast (reachability) distance;
-- that one gates whether audio data reaches this client AT ALL, this one
-- shapes how it fades with distance once it has. Kept smaller than the
-- server's per-mode radius (see VoiceService.lua's own comment) so nobody
-- is ever audible at a hard 0 the instant the server's cutoff is reached.
local MODE_LOCAL_DISTANCE = {
    [Enums.VoiceMode.WHISPER] = 12,
    [Enums.VoiceMode.TALK] = 40,
    [Enums.VoiceMode.SHOUT] = 90,
}
local DEFAULT_LOCAL_DISTANCE = MODE_LOCAL_DISTANCE[Enums.VoiceMode.TALK]
local FADE_DISTANCE_RATIO = 0.75
local POP_SMOOTHING_MS = 800
local MIN_PAN_DISTANCE = 5
local PAN_LIMIT_MIN = 0.35
local MAX_NEARBY_SPEAKERS = 5
-- onClientPlayerVoiceStart/Stop fire far more often than "once per
-- utterance" while someone is continuously talking (documented MTA
-- behavior, "inconsistent triggering" - issue #1700) - a real Stop right
-- after the last real Stop before it, over and over, for as long as
-- someone keeps talking. This is harmless for talking/talkingOrder below
-- (audio), but made the HUD's nearby-speaker list/wave flicker on/off
-- rapidly instead of staying lit for the sentence. HUD_DEBOUNCE_MS is
-- purely cosmetic delay-before-hide for the HUD-facing list ONLY (see
-- hudTalking/hudTalkingOrder below) - audio never waits on this.
local HUD_DEBOUNCE_MS = 1000

--- @param speaker element
-- @return string one of Enums.VoiceMode's values
local function speakerMode(speaker)
    local mode = getElementData(speaker, ElementData.Player.VOICE_MODE)
    return MODE_LOCAL_DISTANCE[mode] and mode or Enums.VoiceMode.TALK
end

-- source player -> true, insertion order preserved via talkingOrder so a
-- removal doesn't require scanning-while-mutating a `pairs()` table (the
-- original version called table.remove(talking, k) from inside a pairs()
-- loop over the same table, which is undefined behavior in Lua). Declared
-- BEFORE VoiceState.isTalking below - Lua's `local` has no hoisting, so a
-- function referencing `talking` while defined above this line would
-- close over the global `talking` (always nil) instead of this table.
-- RAW state, flips immediately on every real onClientPlayerVoiceStart/Stop
-- - audio (onClientRender below) reads this directly, on purpose.
local talking = {}
local talkingOrder = {}

-- Separate, DEBOUNCED copy of the same idea, HUD-facing only - a player
-- only leaves this table (and the resulting CEF push) HUD_DEBOUNCE_MS
-- after their last real onClientPlayerVoiceStop with no restart in
-- between. Entirely independent of talking/talkingOrder above; never
-- read by the audio loop.
local hudTalking = {}
local hudTalkingOrder = {}
local hudStopTimers = {}

--- Public read of whether `player` (any player, not just localPlayer) is
--- currently talking, per THIS client's own tracking - other resources
--- (ui_hud) should call this instead of reading ElementData.Player.VOICE
--- directly, so gm_voice can change how it tracks talking state later
--- without every caller needing to follow along. Reads the debounced HUD
--- state, not the raw one - ui_hud's own mic glow would otherwise flicker
--- on the same rapid-fire stop/restart pairs the HUD list debounces.
-- @param player element
-- @return boolean
VoiceState.isTalking = function(player)
    return hudTalking[player] == true
end

--- @param player element
-- @return string one of Enums.VoiceMode's values
VoiceState.getMode = function(player)
    return speakerMode(player)
end

function voiceStateIsTalking(player) return VoiceState.isTalking(player) end
function voiceStateGetMode(player) return VoiceState.getMode(player) end

local function removeFromOrder(player)
    for index, value in ipairs(talkingOrder) do
        if value == player then
            table.remove(talkingOrder, index)
            return
        end
    end
end

local function removeFromHudOrder(player)
    for index, value in ipairs(hudTalkingOrder) do
        if value == player then
            table.remove(hudTalkingOrder, index)
            return
        end
    end
end

--- Pushes the current hudTalkingOrder (name + mode, capped) to the CEF
--- HUD. Called on every HUD-visible talking-list change, not per-frame.
local function pushNearbySpeakers()
    local speakers = {}
    for _, speaker in ipairs(hudTalkingOrder) do
        if #speakers >= MAX_NEARBY_SPEAKERS then
            break
        end
        if isElement(speaker) then
            speakers[#speakers + 1] = { name = getPlayerName(speaker), mode = speakerMode(speaker) }
        end
    end

    exports.core_ui:uiPushEvent(Events.PUSH_VOICE_NEARBY_UPDATED, { speakers = speakers })
end

--- Cancels `player`'s pending "remove from the HUD" debounce timer, if any.
-- @param player element
local function cancelHudStopTimer(player)
    local timer = hudStopTimers[player]
    if timer and isTimer(timer) then
        killTimer(timer)
    end
    hudStopTimers[player] = nil
end

--- Marks `player` as HUD-visibly talking right now - adds them if they
--- weren't already, and cancels any pending debounce removal (the common
--- case: a rapid-fire spurious restart mid-sentence).
-- @param player element
local function markHudTalking(player)
    cancelHudStopTimer(player)

    if hudTalking[player] then
        return
    end

    hudTalking[player] = true
    hudTalkingOrder[#hudTalkingOrder + 1] = player
    pushNearbySpeakers()
end

--- Schedules `player`'s HUD-visible removal after HUD_DEBOUNCE_MS, unless
--- cancelled by another markHudTalking call in the meantime.
-- @param player element
local function scheduleHudStop(player)
    cancelHudStopTimer(player)
    hudStopTimers[player] = setTimer(function()
        hudStopTimers[player] = nil
        hudTalking[player] = nil
        removeFromHudOrder(player)
        pushNearbySpeakers()
    end, HUD_DEBOUNCE_MS, 1)
end

addEventHandler("onClientPlayerVoiceStart", root, function()
    markHudTalking(source)

    if talking[source] then
        return
    end

    talking[source] = true
    talkingOrder[#talkingOrder + 1] = source
    setElementData(source, ElementData.Player.VOICE, true, false)
    setElementData(source, ElementData.Player.VOICE_START, getTickCount(), false)
    setSoundVolume(source, 0)
end)

addEventHandler("onClientPlayerVoiceStop", root, function()
    if not talking[source] then
        return
    end

    scheduleHudStop(source)

    talking[source] = nil
    removeFromOrder(source)

    if isElement(source) then
        setElementData(source, ElementData.Player.VOICE, false, false)
    end
end)

addEventHandler("onClientPlayerQuit", root, function()
    cancelHudStopTimer(source)
    if hudTalking[source] then
        hudTalking[source] = nil
        removeFromHudOrder(source)
        pushNearbySpeakers()
    end

    if talking[source] then
        talking[source] = nil
        removeFromOrder(source)
    end
end)

--- Panning replicates MTA client's own internal formula (see the C++
--- reference in the project history) so scripted panning matches the
--- built-in voice resource's feel: pan sharpness ramps in as the speaker
--- gets close, capped by panLimit so nearby speakers don't hard-pan L/R.
-- @param speaker element
-- @param distance number
local function applyPanning(speaker, distance)
    local panSharpness = MathHelpers.unlerpClamped(MIN_PAN_DISTANCE, distance, distance * 2)
    local panLimit = MathHelpers.lerp(PAN_LIMIT_MIN, panSharpness, 1.0)

    local cx, cy, cz, clx, cly, clz = getCameraMatrix()
    local camPos = Vector3(cx, cy, cz)

    local look = (Vector3(clx, cly, clz) - camPos)
    local toSpeaker = (Vector3(getElementPosition(speaker)) - camPos)
    look.z = 0
    toSpeaker.z = 0
    look = look:getNormalized()
    toSpeaker = toSpeaker:getNormalized()

    local pan = MathHelpers.clamp(-panLimit, -(look:cross(toSpeaker)).z, panLimit)
    setSoundPan(speaker, pan)
end

addEventHandler("onClientRender", root, function()
    if #talkingOrder == 0 then
        return
    end

    local cx, cy, cz = getCameraMatrix()
    local now = getTickCount()

    for _, speaker in ipairs(talkingOrder) do
        if isElement(speaker) then
            local distance = getDistanceBetweenPoints3D(cx, cy, cz, getElementPosition(speaker))
            local localDistance = MODE_LOCAL_DISTANCE[speakerMode(speaker)] or DEFAULT_LOCAL_DISTANCE

            if distance <= localDistance then
                local fade = localDistance * FADE_DISTANCE_RATIO
                local progress = (distance - fade) / (localDistance - fade)
                local volume = MathHelpers.clamp(0, BASE_VOLUME - (BASE_VOLUME * progress), BASE_VOLUME)

                local start = getElementData(speaker, ElementData.Player.VOICE_START) or now
                local popSmoothing = math.min(1, (now - start) / POP_SMOOTHING_MS)

                setSoundVolume(speaker, volume * popSmoothing)
                applyPanning(speaker, distance)
            else
                setSoundVolume(speaker, 0)
            end
        end
    end
end)
