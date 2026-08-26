local screenW, screenH = guiGetScreenSize()

local IMAGE_PATH = dxCreateTexture("assets/lights.png")

-- getSoundFFTData's own iSamples must be a power of 2 between 512-16384;
-- 1024 is plenty of frequency resolution for "how much bass is there
-- right now" without costing much per-frame. iBands controls how many
-- bands the 1024 samples get bucketed into - 32 keeps LOW_BAND_COUNT (the
-- sub-bass/kick-drum range) a small, cheap slice to sum every frame.
local FFT_SAMPLES = 1024
local FFT_BANDS = 32
local LOW_BAND_COUNT = 3 -- roughly sub-bass/kick-drum range out of 32 bands

-- Dual-average onset detection (a standard "spectral flux" approach) -
-- a SINGLE rolling average against a fixed multiplier isn't enough here:
-- a sustained/droning bassline sits at a roughly CONSTANT low-band
-- energy, so once the single average catches up to that constant level,
-- the bassline's own normal jitter starts crossing the multiplier
-- threshold on its own, firing flashes for "the bass is present" instead
-- of "a kick just hit". Two windows fix this:
--   - FAST window: very short, tracks the CURRENT instant closely.
--   - SLOW window: long, tracks the recent "typical" level (rises/falls
--     slowly, so it stays roughly flat under a steady bassline).
-- A kick is FAST spiking well above SLOW - exactly the moment energy
-- jumps, not the steady-state level a sustained bass note sits at.
local FAST_WINDOW_SAMPLES = 3
local SLOW_WINDOW_SAMPLES = 43

-- FAST must exceed SLOW by this multiplier to count as a kick.
local ONSET_MULTIPLIER = 1.8
-- FAST must also exceed SLOW by this much in absolute terms - without an
-- absolute floor, a near-silent passage (tiny SLOW) would let a tiny FAST
-- blip satisfy the multiplier alone and fire on noise-floor jitter.
local MIN_ONSET_DELTA = 0.015
local MIN_ENERGY = 0.02

local ONSET_COOLDOWN_MS = 300
local FLASH_DURATION_MS = 1650
local FLASH_EASING = "Linear"

local recentEnergies = {}
local lastOnsetTick = 0
local currentAlpha = 0
local flashAnim = nil

--- @return number sum of the lowest LOW_BAND_COUNT FFT bands for
--         `sound`'s CURRENT frame, 0 if FFT data isn't available (e.g.
--         the sound hasn't started streaming yet).
local function readLowBandEnergy(sound)
    local fft = getSoundFFTData(sound, FFT_SAMPLES, FFT_BANDS)
    if not fft then
        return 0
    end

    local energy = 0
    for i = 1, LOW_BAND_COUNT do
        energy = energy + (fft[i] or 0)
    end
    return energy
end

--- @param count number how many of the most recent samples to average
--        (from the END of recentEnergies) - count > #recentEnergies
--        just averages everything available.
-- @return number 0 if recentEnergies is empty.
local function averageOfLast(count)
    local total = #recentEnergies
    if total == 0 then
        return 0
    end

    local start = math.max(1, total - count + 1)
    local sum = 0
    local n = 0
    for i = start, total do
        sum = sum + recentEnergies[i]
        n = n + 1
    end
    return sum / n
end

local function pushEnergy(value)
    recentEnergies[#recentEnergies + 1] = value
    if #recentEnergies > SLOW_WINDOW_SAMPLES then
        table.remove(recentEnergies, 1)
    end
end

--- Starts (or restarts, if one is already mid-flash) the alpha 1->0
--- flash animation - AnimationManager handles the actual per-frame
--- interpolation/onClientRender wiring (see UiAnimation.lua).
local function triggerFlash()
    if flashAnim and not AnimationManager.isFinished(flashAnim) then
        AnimationManager.remove(flashAnim)
    end

    currentAlpha = 1
    flashAnim = AnimationManager.create(1, 0, FLASH_EASING, FLASH_DURATION_MS, function(value)
        currentAlpha = value
    end)
end

local function updateKickDetection()
    local sound = musicStateGetCurrentSound()
    if not sound then
        return
    end

    local energy = readLowBandEnergy(sound)
    -- Push BEFORE reading fast/slow - fast must include the current
    -- sample (it's a "right now" average), and with FAST_WINDOW_SAMPLES
    -- this small, the one-sample lag from pushing first vs. last makes
    -- no audible/visual difference to the slow average either.
    pushEnergy(energy)

    local fast = averageOfLast(FAST_WINDOW_SAMPLES)
    local slow = averageOfLast(SLOW_WINDOW_SAMPLES)

    local now = getTickCount()
    local delta = fast - slow
    if fast >= MIN_ENERGY and slow > 0 and fast >= slow * ONSET_MULTIPLIER and delta >= MIN_ONSET_DELTA and now - lastOnsetTick >= ONSET_COOLDOWN_MS then
        lastOnsetTick = now
        triggerFlash()
    end
end

local function drawLights()
    if currentAlpha <= 0 then
        return
    end

    dxDrawImage(0, 0, screenW, screenH, IMAGE_PATH, 0, 0, 0, tocolor(255, 255, 255, math.floor(currentAlpha * 255)))
end

local function render()
    local sound = musicStateGetCurrentSound()
    if not sound then
        return
    end

    updateKickDetection()
    drawLights()
end

addEventHandler("onClientRender", root, render)
addEventHandler("onClientPlayerSpawn", localPlayer, function()
    removeEventHandler("onClientRender", root, render)
end)