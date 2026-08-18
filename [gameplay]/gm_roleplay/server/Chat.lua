local GRAY = "#AAAAAA"
local CHAT_RANGE = 30

local function escapeColorCodes(text)
    return text:gsub("#(%x%x%x%x%x%x)", "# %1")
end

--- @param sender element
-- @param listener element
-- @return boolean true if `listener` should hear `sender` - same dimension/interior and within CHAT_RANGE (3D)
local function isWithinChatRange(sender, listener)
    if listener == sender then
        return true
    end

    if getElementDimension(listener) ~= getElementDimension(sender) then
        return false
    end
    if getElementInterior(listener) ~= getElementInterior(sender) then
        return false
    end

    local sx, sy, sz = getElementPosition(sender)
    local lx, ly, lz = getElementPosition(listener)
    return getDistanceBetweenPoints3D(sx, sy, sz, lx, ly, lz) <= CHAT_RANGE
end

--- @param player element authenticated player
-- @return string "#RRGGBB"
local function colorForPlayer(player)
    if not player or not isElement(player) then
        return "#FFFFFF"
    end

    local logged = getElementData(player, ElementData.Player.LOGGED)
    local spawned = getElementData(player, ElementData.Player.SPAWNED)
    if not logged or not spawned then
        return "#FFFFFF"
    end

    local r, g, b = getPlayerNametagColor(player)
    if not r then
        return "#FFFFFF"
    end
    return ("#%02X%02X%02X"):format(r, g, b)
end

addEventHandler("onPlayerChat", root, function(message, messageType)
    cancelEvent()

    -- messageType 0 is normal chat ("say"); other built-in types are left untouched.
    if messageType ~= 0 then
        return
    end

    local logged = getElementData(source, ElementData.Player.LOGGED)
    local spawned = getElementData(source, ElementData.Player.SPAWNED)
    if not logged or not spawned then
        return
    end

    local mute = getElementData(source, ElementData.Account.MUTE)

    if mute then
        local until_ = type(mute.expiresAt) == "string"
            and AccountService.formatExpiryForDisplay(mute.expiresAt)
            or "bezterminowo"

        outputChatBox(
            ("#FF0000Nie możesz pisać na czacie. Twoje konto ma aktywne wyciszenie do %s.%s"):format(
                until_,
                mute.reason and (" Powód: " .. mute.reason) or ""
            ),
            source,
            255, 255, 255,
            true
        )
        return
    end

    local id = getElementData(source, ElementData.Player.ID)
    local nameColor = colorForPlayer(source)
    local safeName = escapeColorCodes(getPlayerName(source))
    local safeMessage = escapeColorCodes(message)

    local line = ("%s%s %s%s#FFFFFF: %s"):format(GRAY, id and tostring(id) or "?", nameColor, safeName, safeMessage)

    for _, listener in ipairs(getElementsByType("player")) do
        if isWithinChatRange(source, listener) then
            outputChatBox(line, listener, 255, 255, 255, true)
        end
    end
end)
