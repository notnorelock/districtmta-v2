-- Custom dx-drawn nametags (name + player id, on-duty rank name/color,
-- status icons, a level placeholder) replacing MTA's own floating
-- nametag entirely - ported from an older, unrelated project's own
-- nametag system, adapted to this project's actual account/duty model
-- (Enums.AccountRole 0-6, PlayerService.isOnDuty - the old code's 0-4
-- "adminRank" scale and always-on rank display don't exist here, see
-- this file's own ROLE_DISPLAY comment). No player level/xp system
-- exists in this project yet (see NametagService.lua's own module
-- comment) - the level shown here is a flat placeholder from the server,
-- not computed client-side.
--
-- Reverted from a 3D-world-billboard (dxDrawMaterialLine3D +
-- dxCreateRenderTarget) attempt back to plain 2D screen-space drawing -
-- the billboard visibly detached from the player's head at certain
-- camera angles (steep up/down look angles degenerate a vertical line's
-- own faceToward orientation) and wasn't worth chasing further. Back to
-- projecting the head bone position to screen space every frame via
-- getScreenFromWorldPosition and drawing plain dxDrawText/dxDrawImage
-- calls directly, gated by isLineOfSightClear for manual occlusion.
NametagState = NametagState or {}

local DRAW_DISTANCE = 40
local FADE_DISTANCE = DRAW_DISTANCE / 1.3
local BASE_ALPHA = 215
local HEAD_BONE_ID = 5

local font = exports.core_ui:getUIFont("regular_normal")
local fontBold = exports.core_ui:getUIFont("bold_normal")

-- Fixed tint per status icon - all four assets (rank/afk/mute/premium.png)
-- are plain grey/white silhouettes specifically so dxDrawImage's own
-- color argument can recolor them like this, rather than shipping a
-- separately-colored asset per status. PREMIUM_COLOR matches
-- PlayerService.lua's own refreshNametagColor gold ({227,176,23}) for the
-- exact same "premium" concept, just applied to an icon tint instead of
-- nickname text color.
local AFK_COLOR = { 149, 165, 166 }
local MUTE_COLOR = { 231, 76, 60 }
local PREMIUM_COLOR = { 227, 176, 23 }
local DEFAULT_COLOR = { 255, 255, 255 }

-- Role display names for on-duty staff only (see the module comment) -
-- PLAYER/VETERAN never go on duty (no TOGGLE_DUTY permission - see
-- Permissions.lua's ROLE_PERMISSIONS), so they have no entry here; a
-- nametag never looks this up unless data.onDuty is true anyway.
local ROLE_DISPLAY_NAME = {
    [Enums.AccountRole.SUPPORTER] = "Support",
    [Enums.AccountRole.MODERATOR] = "Moderator",
    [Enums.AccountRole.ADMINISTRATOR] = "Administrator",
    [Enums.AccountRole.RCON] = "Zarząd RCON",
    [Enums.AccountRole.BOARD] = "Zarząd",
}

-- player -> { id, name, role, onDuty, color = {r,g,b}|nil, level, afk,
-- muted, premium } - every field only changes on NAMETAG_DATA_RECEIVED
-- (server-authoritative - see NametagService.lua's own module comment on
-- why afk/muted/premium are routed through the server too, not read off
-- ElementData directly here).
local iconsTextures = {}
local streamedPlayers = {}
local renderHandlerAttached = false

--- @param hex string|nil "#RRGGBB"
-- @return number, number, number r, g, b - 255,255,255 (white) if hex is
--         nil/malformed, matching an off-duty/no-fixed-color player's
--         plain white name.
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

--- Draws `text` left-aligned starting at `x` at `y`, with a 1px black
--- drop shadow - every text line in this nametag uses this same
--- shadow+left-aligned convention, so it's factored out instead of
--- repeated per line.
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

                    -- Big id.png icon on the left (tinted the on-duty
                    -- role color, numeric id centered on it), a vertical
                    -- text block to its right: if on duty with a rank
                    -- name, that's "Nick" (smaller) stacked above the rank
                    -- name (in its role color); if NOT on duty (no rank
                    -- line to show), "Nick" alone is drawn BIGGER/
                    -- emphasized instead, vertically centered on the icon
                    -- - a lone name carries more visual weight than a
                    -- name that's only half of a two-line block. Status
                    -- icons (afk/mute/premium, only whichever apply) sit
                    -- in their own row above all of this. Every icon asset
                    -- is a plain grey/white silhouette so dxDrawImage's
                    -- own color tint recolors it per status (id.png
                    -- toward the on-duty role color like the role name
                    -- text, the rest toward their own fixed
                    -- MUTE_COLOR/AFK_COLOR/PREMIUM_COLOR) rather than
                    -- shipping a separately-colored asset per status.
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
                    -- White with a black shadow (same convention as every
                    -- other text in this file) rather than a fixed black -
                    -- id.png is tinted to dutyColor above, which can
                    -- itself be dark (e.g. ADMINISTRATOR's red), so plain
                    -- black text would go unreadable against it.
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

--- @param player element
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

--- @param player element
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
