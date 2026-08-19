-- Binds "B" to cycle the local player's voice talk mode
-- (whisper/talk/shout). The server is authoritative over the resulting
-- mode (VoiceService.lua) - this only requests a cycle and reflects
-- whatever the server confirms via chat, it never sets the mode itself.
VoiceModeState = VoiceModeState or {}

local KEY = "b"

local function requestCycleMode()
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
        return
    end
    triggerServerEvent(Events.VOICE_CYCLE_MODE, resourceRoot)
end

bindKey(KEY, "down", requestCycleMode)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey(KEY, "down", requestCycleMode)
end)
