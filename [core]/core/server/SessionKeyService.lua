local sessionKeys = {}

-- generateString is NOT an MTA built-in (a community wiki snippet, not a
-- native function). Seeded once at module load rather than per call -
-- reseeding per-call risks two keys generated in the same tick being
-- identical.
local ALLOWED_BYTE_RANGES = { { 48, 57 }, { 65, 90 }, { 97, 122 } } -- 0-9, A-Z, a-z
math.randomseed(getTickCount())

local function generateRandomString(length)
    local chars = {}
    for i = 1, length do
        local range = ALLOWED_BYTE_RANGES[math.random(1, 3)]
        chars[i] = string.char(math.random(range[1], range[2]))
    end
    return table.concat(chars)
end

local function generateSessionKey()
    -- Not documented/guaranteed cryptographically secure - fine here, see
    -- the module comment above on why this is obfuscation, not real
    -- cryptography.
    return generateRandomString(32)
end

--- @param player element
-- @return string|nil the player's current session key, or nil if none issued yet
function getSessionKey(player)
    return sessionKeys[player]
end

local function issueSessionKey(player)
    if not player or not isElement(player) then
        return nil
    end

    local key = getElementData(player, ElementData.Player.SESSION_KEY) or generateSessionKey()
    if key then
        sessionKeys[player] = key
        setElementData(player, ElementData.Player.SESSION_KEY, key, false)

        Logger.debug("SessionKeyService", "Session key issued", { player = getPlayerName(player) })
        return key
    else
        Logger.warn("SessionKeyService", "Failed to issue session key", { player = getPlayerName(player) })
        return nil
    end
end

addEventHandler("onPlayerJoin", root, function()
    issueSessionKey(source)
end)

addEventHandler("onPlayerQuit", root, function()
    sessionKeys[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if not sessionKeys[player] then
            issueSessionKey(player)
        end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    sessionKeys = {}
end)
