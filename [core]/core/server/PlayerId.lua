-- Short, stable runtime id per connected player (e.g. "/ban 5") - see
-- docs/Architecture.md's "Player lookup" section.
PlayerId = PlayerId or {}

local ID_ELEMENT_DATA_KEY = ElementData.Player.ID

-- id -> player element
local playersById = {}

--- @return number the smallest runtime id not currently in use
local function nextFreeId()
    local id = 1
    while isElement(playersById[id]) do
        id = id + 1
    end
    return id
end

local function assignId(player)
    if not isElement(player) then
        return
    end

    local id = nextFreeId()
    playersById[id] = player
    setElementData(player, ID_ELEMENT_DATA_KEY, id)
end

local function releaseId(player)
    local id = getElementData(player, ID_ELEMENT_DATA_KEY)
    if type(id) == "number" and playersById[id] == player then
        playersById[id] = nil
    end
end

--- @param id number
-- @return element|nil
PlayerId.byId = function(id)
    local player = playersById[id]
    return isElement(player) and player or nil
end

--- @param player element
-- @return number|nil
PlayerId.of = function(player)
    local id = getElementData(player, ID_ELEMENT_DATA_KEY)
    return type(id) == "number" and id or nil
end

--- Case-insensitive substring match against every connected player's
--- name, with MTA color codes (#RRGGBB) stripped first so a color-coded
--- nickname still matches on its visible text.
-- @param fragment string
-- @return element|nil match, boolean ambiguous - ambiguous is true when
--         more than one player matched (match is nil in that case)
local function byNameFragment(fragment)
    local needle = fragment:lower()
    local match = nil

    for _, candidate in ipairs(getElementsByType("player")) do
        local visibleName = getPlayerName(candidate):gsub("#%x%x%x%x%x%x", ""):lower()
        if visibleName:find(needle, 1, true) then
            if match then
                return nil, true
            end
            match = candidate
        end
    end

    return match, false
end

--- Same lookup as PlayerId.resolve, but silent - never sends a notification.
-- @param target string|number either a runtime id or a name fragment
-- @return element|nil match, boolean ambiguous
PlayerId.tryResolve = function(target)
    if target == nil or target == "" then
        return nil, false
    end

    local asNumber = tonumber(target)
    if asNumber then
        return PlayerId.byId(asNumber), false
    end

    return byNameFragment(tostring(target))
end

--- Sends `player` an error notification and returns nil on failure.
-- @param player element the admin issuing the lookup, for error feedback
-- @param target string|number either a runtime id or a name fragment
-- @return element|nil
PlayerId.resolve = function(player, target)
    if not isElement(player) then
        return nil
    end

    local resolved, ambiguous = PlayerId.tryResolve(target)
    if resolved then
        return resolved
    end

    NotificationService.send(player, {
        type = Enums.NotificationType.ERROR,
        title = ambiguous and "Znaleziono więcej niż jednego gracza" or "Nie znaleziono gracza",
        message = ambiguous and "Podaj więcej liter nicku lub użyj numeru gracza." or nil,
    })
    return nil
end

local function start()
    for _, player in ipairs(getElementsByType("player")) do
        assignId(player)
    end

    addEventHandler("onPlayerJoin", root, function()
        assignId(source)
    end)

    addEventHandler("onPlayerQuit", root, function()
        releaseId(source)
    end)
end

addEventHandler("onResourceStart", resourceRoot, start)

function playerIdById(id) return PlayerId.byId(id) end
function playerIdOf(player) return PlayerId.of(player) end
function playerIdResolve(player, target) return PlayerId.resolve(player, target) end
