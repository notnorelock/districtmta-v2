-- Shared tween driver every HUD component/notification animates through
-- (position/alpha/scale/color) - ported from an older, unrelated project's
-- own animate.lua (MTA class()/instanceof() Animation/AnimationManager
-- classes, plus a ColorAnim class - dropped here since nothing in this
-- port ever passes a ColorAnim as from/to, see HUDComponent.lua's own
-- animateColor which always animates 4 separate plain-number animations
-- instead) to a plain module table, matching this project's own style.
-- Built entirely on MTA's native interpolateBetween (this project already
-- uses it elsewhere, e.g. [custom]/markers/client/marker.lua's ground
-- pulse) - no external easing dependency.
AnimationManager = AnimationManager or {}

local animations = {}
local renderHandlerAttached = false
local updateAll

local function attachIfNeeded()
    if not renderHandlerAttached then
        addEventHandler("onClientRender", root, updateAll)
        renderHandlerAttached = true
    end
end

local function detachIfIdle()
    if renderHandlerAttached and #animations == 0 then
        removeEventHandler("onClientRender", root, updateAll)
        renderHandlerAttached = false
    end
end

-- @return boolean true once the animation has reached/passed its duration
local function updateOne(anim)
    if anim.paused or anim.finished then
        return false
    end

    local elapsed = getTickCount() - anim.startTime
    local progress = math.min(elapsed / anim.duration, 1)

    anim.currentValue = interpolateBetween(anim.from, 0, 0, anim.to, 0, 0, progress, anim.easing)

    if anim.onUpdate then
        anim.onUpdate(anim.currentValue)
    end

    if progress >= 1 then
        anim.finished = true
        if anim.onEnd then
            anim.onEnd()
        end
        return true
    end

    return false
end

updateAll = function()
    for i = #animations, 1, -1 do
        if updateOne(animations[i]) then
            table.remove(animations, i)
        end
    end

    detachIfIdle()
end

--- @param from number
-- @param to number
-- @param easing string any MTA interpolateBetween easing type (e.g. "Linear", "InOutQuad")
-- @param duration number milliseconds
-- @param onUpdate function|nil called with the current interpolated value every frame
-- @param onEnd function|nil called once when the animation completes
-- @return table an animation handle, pass to AnimationManager.remove to cancel early
AnimationManager.create = function(from, to, easing, duration, onUpdate, onEnd)
    local anim = {
        from = from,
        to = to,
        easing = easing or "Linear",
        duration = duration or 1000,
        onUpdate = onUpdate,
        onEnd = onEnd,

        startTime = getTickCount(),
        paused = false,
        pauseTime = 0,
        finished = false,
        currentValue = from,
    }

    animations[#animations + 1] = anim
    attachIfNeeded()

    return anim
end

--- @param anim table a handle returned by AnimationManager.create
-- @return boolean true if it was found and removed
AnimationManager.remove = function(anim)
    for i = #animations, 1, -1 do
        if animations[i] == anim then
            table.remove(animations, i)
            detachIfIdle()
            return true
        end
    end
    return false
end

--- @param anim table a handle returned by AnimationManager.create
AnimationManager.pause = function(anim)
    if not anim.paused then
        anim.paused = true
        anim.pauseTime = getTickCount()
    end
end

--- @param anim table a handle returned by AnimationManager.create
AnimationManager.resume = function(anim)
    if anim.paused then
        anim.startTime = anim.startTime + (getTickCount() - anim.pauseTime)
        anim.paused = false
    end
end

--- @param anim table a handle returned by AnimationManager.create
--         Jumps straight to the end value/onEnd without waiting out the
--         remaining duration. Does NOT remove it from the manager itself
--         (matches the ported original's behavior) - call
--         AnimationManager.remove separately if needed.
AnimationManager.finish = function(anim)
    anim.currentValue = anim.to
    if anim.onUpdate then
        anim.onUpdate(anim.to)
    end
    if anim.onEnd then
        anim.onEnd()
    end
    anim.finished = true
end

--- @param anim table a handle returned by AnimationManager.create
-- @return boolean
AnimationManager.isFinished = function(anim)
    return anim.finished
end

--- @param anim table a handle returned by AnimationManager.create
-- @return number the last interpolated value
AnimationManager.getValue = function(anim)
    return anim.currentValue
end

AnimationManager.clear = function()
    animations = {}
    detachIfIdle()
end

--- @return number
AnimationManager.getCount = function()
    return #animations
end

-- Legacy global function support (matches the ported original's own
-- top-level createAnimation/deleteAnimation/finishAnimation helpers).
function createAnimation(from, to, easing, duration, onUpdate, onEnd)
    return AnimationManager.create(from, to, easing, duration, onUpdate, onEnd)
end

function deleteAnimation(anim)
    return AnimationManager.remove(anim)
end

function finishAnimation(anim)
    AnimationManager.finish(anim)
    return AnimationManager.remove(anim)
end
