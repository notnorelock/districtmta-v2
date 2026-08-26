local FADE_DURATION_MS = 4000
local FADE_STEP_MS = 100
local VOLUME = 0.5

local sound = nil
local fadeTimer = nil

local function stopMusic()
    if isTimer(fadeTimer) then
        killTimer(fadeTimer)
    end
    fadeTimer = nil

    if sound and isElement(sound) then
        destroyElement(sound)
    end
    sound = nil
end

local function startMusic()
    stopMusic()

    sound = playSound("assets/music.mp3", true, false)
    if not sound then
        return
    end
    setSoundVolume(sound, VOLUME)
end

local function fadeOutMusic()
    if not sound or not isElement(sound) then
        return
    end

    local thisSound = sound
    local steps = FADE_DURATION_MS / FADE_STEP_MS
    local stepsDone = 0

    fadeTimer = setTimer(function()
        if not isElement(thisSound) then
            return
        end

        stepsDone = stepsDone + 1
        local remaining = math.max(0, 1 - (stepsDone / steps))
        setSoundVolume(thisSound, VOLUME * remaining)

        if remaining <= 0 then
            fadeTimer = nil
            destroyElement(thisSound)
            if sound == thisSound then
                sound = nil
            end
        end
    end, FADE_STEP_MS, steps)
end

-- Read by LightsEffect.lua (a separate Lua chunk in this same resource -
-- `sound` above is a `local`, invisible across files, see AGENTS.md's
-- own gotcha on that) to run its FFT kick-detector against whatever's
-- currently playing. Returns nil while nothing is playing/mid-fade-out
-- teardown, which LightsEffect.lua treats as "nothing to analyze".
function musicStateGetCurrentSound()
    return sound and isElement(sound) and sound or nil
end

addEvent(Events.AUTH_BEGIN_AUTHENTICATION, true)
addEventHandler(Events.AUTH_BEGIN_AUTHENTICATION, root, startMusic)

addEventHandler("onClientPlayerSpawn", localPlayer, fadeOutMusic)

addEventHandler("onClientResourceStop", resourceRoot, stopMusic)
