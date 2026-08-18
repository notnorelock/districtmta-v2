local sessionKeys = {}
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
    local timestamp = getRealTime().timestamp
    local randomString = generateRandomString(64)

    local key = sha256(string.format("%d:%s", timestamp, randomString))
    iprint("Generated session key:", key)
    return key
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

    sessionKeys[player] = generateSessionKey()
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
