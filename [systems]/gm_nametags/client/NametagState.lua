local AFK_COLOR = { 149, 165, 166 }
local MUTE_COLOR = { 231, 76, 60 }
local PREMIUM_COLOR = { 227, 176, 23 }
local DEFAULT_COLOR = { 255, 255, 255 }

local DRAW_DISTANCE = 40
local FADE_DISTANCE = DRAW_DISTANCE / 1.3
local BASE_ALPHA = 215
local HEAD_BONE_ID = 5

local ROLE_DISPLAY_NAME = {
    [Enums.AccountRole.SUPPORTER] = "Support",
    [Enums.AccountRole.MODERATOR] = "Moderator",
    [Enums.AccountRole.ADMINISTRATOR] = "Administrator",
    [Enums.AccountRole.RCON] = "Zarząd RCON",
    [Enums.AccountRole.BOARD] = "Zarząd",
}

local font = exports.core_ui:getUIFont("regular_normal")
local fontBold = exports.core_ui:getUIFont("bold_normal")

local iconsTextures = {}
local streamedPlayers = {}
local renderHandlerAttached = false

local function rgbFromHex(hex)
    if type(hex) ~= "string" then
        return 255, 255, 255
    end
    local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then
        return 255, 255, 255
    end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function requestNametagData(player)
    if not isElement(player) or getElementType(player) ~= "player" then
        return
    end

    triggerServerEvent(Events.NAMETAG_REQUEST_DATA, resourceRoot, player)
end

local function drawLeftText(text, x, y, scale, textFont, color, alpha)
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, alpha), scale, textFont, "left", "center", false, false, false, true)
    dxDrawText(text, x, y, x, y, tocolor(color[1], color[2], color[3], alpha), scale, textFont, "left", "center", false, false, false, true)
end

local function renderNametags()
    local cx, cy, cz = getCameraMatrix()

    for player, data in pairs(streamedPlayers) do
        if isElement(player) then
            local px, py, pz = getPedBonePosition(player, HEAD_BONE_ID)
            local distance = getDistanceBetweenPoints3D(cx, cy, cz, px, py, pz)

            if distance < DRAW_DISTANCE then
                local sx, sy = getScreenFromWorldPosition(px, py, pz + 0.25, 0.2)

                if sx and sy and isLineOfSightClear(cx, cy, cz, px, py, pz, true, false, false, true, false, false, true, nil) then
                    local progress = (distance - FADE_DISTANCE) / (DRAW_DISTANCE - FADE_DISTANCE)
                    local alpha = math.max(0, math.min(BASE_ALPHA - (BASE_ALPHA * progress), BASE_ALPHA)) * (getElementAlpha(player) / 255)
                    local textScale = math.max(0.45, 0.75 - (distance * 0.02))

                    local dutyColor = (data.onDuty and data.color or data.premium and PREMIUM_COLOR or data.color) or DEFAULT_COLOR
                    local roleName = data.onDuty and ROLE_DISPLAY_NAME[data.role] or nil

                    local statusIcons = {}
                    if data.afk then
                        statusIcons[#statusIcons + 1] = { key = "afk", color = AFK_COLOR }
                    end
                    if data.onDuty then
                        statusIcons[#statusIcons + 1] = { key = "rank", color = dutyColor }
                    end
                    if data.muted then
                        statusIcons[#statusIcons + 1] = { key = "mute", color = MUTE_COLOR }
                    end
                    if data.premium then
                        statusIcons[#statusIcons + 1] = { key = "premium", color = PREMIUM_COLOR }
                    end

                    local idIconSize = 44 * textScale
                    local textGap = 4 * textScale
                    local nameScale = roleName and textScale or textScale * 1.35
                    local nameText = data.name
                    local nameWidth = dxGetTextWidth(nameText, nameScale, roleName and font or fontBold)
                    local blockWidth = idIconSize + textGap + nameWidth
                    local leftX = sx - blockWidth / 2

                    if #statusIcons > 0 then
                        local iconSize = 36 * textScale
                        local iconGap = -4 * textScale
                        local iconY = sy - 62 * textScale
                        local iconX = leftX + 2

                        for _, icon in ipairs(statusIcons) do
                            dxDrawImage(iconX, iconY, iconSize, iconSize, iconsTextures[icon.key], 0, 0, 0, tocolor(icon.color[1], icon.color[2], icon.color[3], alpha))
                            iconX = iconX + iconSize + iconGap
                        end
                    end

                    local blockCenterY = sy - 6 * textScale
                    local idIconY = blockCenterY - idIconSize / 2
                    dxDrawImage(leftX, idIconY, idIconSize, idIconSize, iconsTextures.id, 0, 0, 0, tocolor(dutyColor[1], dutyColor[2], dutyColor[3], alpha))

                    local idText = tostring(data.id)
                    dxDrawText(idText, leftX + 1, idIconY + 1, leftX + idIconSize + 1, idIconY + idIconSize + 1, tocolor(0, 0, 0, alpha), textScale, fontBold, "center", "center")
                    dxDrawText(idText, leftX, idIconY, leftX + idIconSize, idIconY + idIconSize, tocolor(255, 255, 255, alpha), textScale, fontBold, "center", "center")

                    local textX = leftX + idIconSize + textGap

                    if roleName then
                        local nameY = blockCenterY - 8 * textScale
                        local roleY = blockCenterY + 8 * textScale
                        drawLeftText(nameText, textX, nameY, nameScale, fontBold, DEFAULT_COLOR, alpha)
                        drawLeftText(roleName, textX, roleY, textScale - 0.08, fontBold, data.color, alpha)
                    else
                        drawLeftText(nameText, textX, blockCenterY, nameScale - 0.18, fontBold, DEFAULT_COLOR, alpha)
                    end
                end
            end
        end
    end
end

local function addNametag(player)
    if not isElement(player) --[[or player == localPlayer]] or streamedPlayers[player] then
        return
    end

    setPlayerNametagShowing(player, false)

    streamedPlayers[player] = {
        id = getElementData(player, ElementData.Player.ID),
        name = getPlayerName(player),
        role = nil,
        onDuty = false,
        color = nil,
        level = "?",
        afk = false,
        muted = false,
        premium = false,
    }
    requestNametagData(player)

    if not renderHandlerAttached then
        addEventHandler("onClientRender", root, renderNametags, true, 'high+9999')
        renderHandlerAttached = true
    end
end

local function removeNametag(player)
    if not streamedPlayers[player] then
        return
    end
    streamedPlayers[player] = nil

    if renderHandlerAttached and not next(streamedPlayers) then
        removeEventHandler("onClientRender", root, renderNametags)
        renderHandlerAttached = false
    end
end

addEvent(Events.NAMETAG_DATA_RECEIVED, true)
addEventHandler(Events.NAMETAG_DATA_RECEIVED, root, function(player, data)
    local entry = streamedPlayers[player]
    if not entry then
        return
    end

    entry.role = data.role
    entry.onDuty = data.onDuty == true
    entry.color = type(data.color) == "string" and { rgbFromHex(data.color) } or nil
    entry.afk = data.afk == true
    entry.muted = data.muted == true
    entry.premium = data.premium == true
    entry.level = data.level
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "player" then
        return
    end
    if getElementData(source, ElementData.Player.SPAWNED) ~= true then
        return
    end
    addNametag(source)
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) ~= "player" then
        return
    end
    removeNametag(source)
end)

addEventHandler("onClientPlayerQuit", root, function()
    removeNametag(source)
end)

addEventHandler("onClientPlayerJoin", root, function()
    setPlayerNametagShowing(source, false)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, k in ipairs({ "id", "rp", "afk", "rank", "mute", "premium" }) do
        local path = string.format("assets/%s.png", k)

        if fileExists(path) and not iconsTextures[k] then
            iconsTextures[k] = dxCreateTexture(path)
        end
    end

    for _, player in ipairs(getElementsByType("player")) do
        -- if player ~= localPlayer then
            setPlayerNametagShowing(player, false)
            if isElementStreamedIn(player) and getElementData(player, ElementData.Player.SPAWNED) == true then
                addNametag(player)
            end
        -- end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if renderHandlerAttached then
        removeEventHandler("onClientRender", root, renderNametags)
        renderHandlerAttached = false
    end

    for k, v in pairs(iconsTextures) do
        if isElement(v) then
            destroyElement(v)
        end
        iconsTextures[k] = nil
    end

    streamedPlayers = {}
    iconsTextures = {}
end)
