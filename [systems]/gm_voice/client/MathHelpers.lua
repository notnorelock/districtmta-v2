-- Small numeric helpers for the voice panning calculation (VoiceState.lua).
-- Own namespace rather than adding fields onto Lua's global `math` table -
-- polluting a standard library table is surprising for anything else that
-- reads math.* and doesn't expect project-specific extensions on it.
MathHelpers = MathHelpers or {}

--- @param from number
-- @param alpha number 0..1
-- @param to number
-- @return number
MathHelpers.lerp = function(from, alpha, to)
    return from + (to - from) * alpha
end

--- @param low number
-- @param value number
-- @param high number
-- @return number value clamped to [low, high]
MathHelpers.clamp = function(low, value, high)
    return math.max(low, math.min(value, high))
end

--- @param from number
-- @param pos number
-- @param to number
-- @return number 0..1+ (unclamped) - 0 at `from`, 1 at `to`
MathHelpers.unlerp = function(from, pos, to)
    if to == from then
        return 1
    end
    return (pos - from) / (to - from)
end

--- @param from number
-- @param pos number
-- @param to number
-- @return number MathHelpers.unlerp result, clamped to [0, 1]
MathHelpers.unlerpClamped = function(from, pos, to)
    return MathHelpers.clamp(0, MathHelpers.unlerp(from, pos, to), 1)
end
