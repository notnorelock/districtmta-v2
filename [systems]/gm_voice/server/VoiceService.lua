-- Proximity voice chat: who can hear whom (interior/dimension/distance-gated
-- broadcast target list, distance itself driven by each speaker's talk
-- mode) and whether a player is allowed to transmit at all (spawned + not
-- muted). Client-side (client/VoiceState.lua) only handles volume
-- falloff/panning for players the server already decided should hear each
-- other - it has no authority over broadcast targets, talk mode, or mute
-- state.
VoiceService = VoiceService or {}

-- Broadcast (server-side "can X even reach Y") distance per mode - kept
-- generously larger than the client's own LOCAL_DISTANCE-per-mode falloff
-- range (VoiceState.lua) so the client never has to hear someone at 0
-- volume; the client's own distance-based fade is what actually makes a
-- shout audible farther than a whisper in practice.
local MODE_BROADCAST_DISTANCE = {
    [Enums.VoiceMode.WHISPER] = 20,
    [Enums.VoiceMode.TALK] = 80,
    [Enums.VoiceMode.SHOUT] = 160,
}

-- Cycle order for Events.VOICE_CYCLE_MODE - whisper -> talk -> shout -> whisper.
local MODE_CYCLE = { Enums.VoiceMode.WHISPER, Enums.VoiceMode.TALK, Enums.VoiceMode.SHOUT }
local MODE_CYCLE_INDEX = {}
for index, mode in ipairs(MODE_CYCLE) do
    MODE_CYCLE_INDEX[mode] = index
end

local MODE_LABEL = {
    [Enums.VoiceMode.WHISPER] = "Szept",
    [Enums.VoiceMode.TALK] = "Mowa",
    [Enums.VoiceMode.SHOUT] = "Krzyk",
}

local BROADCAST_SWEEP_INTERVAL_MS = 1000

if not isVoiceEnabled() then
    Logger.info("VoiceService", "Voice chat disabled in server config - gm_voice is a no-op this session")
    return
end

--- @param player element
-- @return string one of Enums.VoiceMode's values - TALK if never set
VoiceService.getMode = function(player)
    local mode = getElementData(player, ElementData.Player.VOICE_MODE)
    return MODE_CYCLE_INDEX[mode] and mode or Enums.VoiceMode.TALK
end

--- @param player element
-- @param mode string one of Enums.VoiceMode's values
VoiceService.setMode = function(player, mode)
    assert(MODE_CYCLE_INDEX[mode], "VoiceService.setMode: invalid mode " .. tostring(mode))
    setElementData(player, ElementData.Player.VOICE_MODE, mode)
end

addEvent(Events.VOICE_CYCLE_MODE, true)
addEventHandler(Events.VOICE_CYCLE_MODE, root, function()
    local player = client
    local currentIndex = MODE_CYCLE_INDEX[VoiceService.getMode(player)]
    local nextMode = MODE_CYCLE[(currentIndex % #MODE_CYCLE) + 1]
    VoiceService.setMode(player, nextMode)

    -- outputChatBox, not a CEF toast (NotificationService) - this can fire
    -- several times in quick succession as a player cycles past the mode
    -- they want, and a toast queue/animation is too heavy for that.
    outputChatBox("Tryb głosu: " .. MODE_LABEL[nextMode], player, 200, 200, 200)
end)

--- Mute is a general account penalty (Enums.PenaltyType.MUTE), not a
--- separate voice-only mute - one admin action silences chat and voice
--- together. PlayerService keeps ElementData.Account.MUTE in sync with the
--- DB via a periodic sweep, so this is a cheap synchronous read rather than
--- a fresh AccountPenaltyService.isMuted DB round-trip per voice attempt.
-- @param player element
-- @return boolean
VoiceService.isMuted = function(player)
    return type(getElementData(player, ElementData.Account.MUTE)) == "table"
end

--- Recomputes and applies each player's voice broadcast target list - as
--- speaker, everyone within THEIR OWN mode's distance, same interior and
--- dimension. setPlayerVoiceBroadcastTo(speaker, listeners) is speaker-
--- centric, so the radius used here has to be the speaker's, not the
--- listener's - a shouting player must reach farther, not just "anyone
--- within whisper range of a shouter still hears them at whisper range".
VoiceService.updateBroadcastTargets = function()
    for _, speaker in ipairs(getElementsByType("player")) do
        local distance = MODE_BROADCAST_DISTANCE[VoiceService.getMode(speaker)]
        local x, y, z = getElementPosition(speaker)
        local nearby = getElementsWithinRange(x, y, z, distance, "player")
        local listeners = {}

        for _, other in ipairs(nearby) do
            if getElementInterior(other) == getElementInterior(speaker)
                and getElementDimension(other) == getElementDimension(speaker) then
                listeners[#listeners + 1] = other
            end
        end

        setPlayerVoiceBroadcastTo(speaker, listeners)
    end
end

setTimer(VoiceService.updateBroadcastTargets, BROADCAST_SWEEP_INTERVAL_MS, 0)

addEventHandler("onResourceStart", resourceRoot, VoiceService.updateBroadcastTargets)

addEventHandler("onPlayerJoin", root, function()
    setPlayerVoiceBroadcastTo(source, root)
end)

local MUTE_NOTICE_COOLDOWN_MS = 10000
local lastMuteNotice = {}

addEventHandler("onPlayerVoiceStart", root, function()
    if getElementData(source, ElementData.Player.SPAWNED) ~= true then
        cancelEvent()
        return
    end

    if VoiceService.isMuted(source) then
        cancelEvent()

        local now = getTickCount()
        if now - (lastMuteNotice[source] or 0) >= MUTE_NOTICE_COOLDOWN_MS then
            lastMuteNotice[source] = now
            NotificationService.send(source, {
                type = "error",
                title = "Wyciszenie",
                message = "Nie możesz mówić na czacie głosowym - Twoje konto jest wyciszone.",
            })
        end

        return
    end
end)

addEventHandler("onPlayerQuit", root, function()
    lastMuteNotice[source] = nil
end)
