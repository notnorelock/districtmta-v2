-- Binds "B" to cycle the local player's voice talk mode
-- (whisper/talk/shout). The server is authoritative over the resulting
-- mode (VoiceService.lua) - this only requests a cycle and reflects
-- whatever the server confirms, it never sets the mode itself.
VoiceModeState = VoiceModeState or {}

local KEY = "b"

local function requestCycleMode()
    if not exports.core_shared:canPlayerInteract(nil, { requiresSpawned = true, inVehicle = false, whileBlackout = false }) then
        return
    end
    triggerServerEvent(Events.VOICE_CYCLE_MODE, resourceRoot)
end

bindKey(KEY, "down", requestCycleMode)

-- Relays the server's confirmation into the CEF HUD - see Events.
-- VOICE_MODE_CHANGED's own comment (used to be a plain outputChatBox
-- line). HudBar.tsx shows this as a transient tooltip over the voice
-- icon, restarting its own auto-hide timer on every push rather than
-- queuing - matches cycling past several modes in quick succession.
addEvent(Events.VOICE_MODE_CHANGED, true)
addEventHandler(Events.VOICE_MODE_CHANGED, root, function(mode, label)
    exports.core_ui:uiPushEvent(Events.PUSH_VOICE_MODE_CHANGED, { mode = mode, label = label })
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey(KEY, "down", requestCycleMode)
end)
