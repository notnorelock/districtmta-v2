-- Custom nametags (name + player id, on-duty rank name/color, status
-- icons, a level placeholder) replacing MTA's own floating nametag
-- entirely - ported from an older, unrelated project's own nametag
-- system, adapted to this project's actual account/duty model
-- (Enums.AccountRole 0-6, PlayerService.isOnDuty - the old code's 0-4
-- "adminRank" scale and always-on rank display don't exist here, see
-- this file's own ROLE_DISPLAY comment). No player level/xp system
-- exists in this project yet (see NametagService.lua's own module
-- comment) - the level shown here is a flat placeholder from the server,
-- not computed client-side.
--
-- Rendered as a true 3D-world billboard via dxDrawMaterialLine3D instead
-- of 2D screen-space dxDrawText/dxDrawImage calls projected via
-- getScreenFromWorldPosition every frame - see renderNametags' own
-- comment for exactly how a vertical line + faceToward=camera becomes a
-- camera-facing quad (dxDrawImage3D would be the simpler wrapper for
-- this, but doesn't exist on this project's MTA version - confirmed live
-- via "attempt to call global 'dxDrawImage3D' (a nil value)" - so this
-- goes straight to the underlying primitive dxDrawImage3D itself wraps,
-- the same one [custom]/markers/client/material.lua's own
-- drawTransformedMaterial already uses elsewhere in this project). The
-- actual name/rank/icon layout is drawn ONCE per player onto that
-- player's own dxCreateRenderTarget (a fixed TEXTURE_WIDTH x
-- TEXTURE_HEIGHT canvas, independent of distance/screen scale), then
-- every onClientRender frame only re-issues a single
-- dxDrawMaterialLine3D call reusing that cached texture - re-rendering
-- the texture's contents only when the underlying data actually changes
-- (see redrawIfDirty/signatureOf). This both means per-frame cost stays
-- at one draw call per visible nametag regardless of how much text/how
-- many icons it has, and gives the nametag real depth-buffer interaction
-- against world geometry (a true 3D quad z-tests naturally) rather than
-- relying solely on the manual isLineOfSightClear occlusion check below
-- (kept anyway as a cheap early reject - a billboard behind a wall would
-- still z-test correctly, but there's no reason to even issue the draw
-- call for it).
NametagState = NametagState or {}

local DRAW_DISTANCE = 40
local FADE_DISTANCE = DRAW_DISTANCE / 1.3
local BASE_ALPHA = 215
local HEAD_BONE_ID = 5

-- Fixed render-target resolution every player's nametag texture is drawn
-- at, regardless of distance - only the WORLD-SPACE size the billboard
-- is drawn at (see worldSizeFor) scales with distance, the same visual
-- effect the old textScale multiplier had, just applied to the 3D quad's
-- own width/height instead of to the 2D drawing calls.
local TEXTURE_WIDTH = 512
local TEXTURE_HEIGHT = 160
-- World-unit size (GTA units, matches getDistanceBetweenPoints3D's own
-- scale) the billboard is drawn at when BASE_TEXT_SCALE's own reference
-- distance conditions apply - scaled by distance in worldSizeFor the same
-- way the old 2D code's textScale = math.max(0.45, 0.75 - distance*0.02)
-- kept screen-space text roughly readable-sized regardless of range.
local BASE_WORLD_WIDTH = 1.1
local BASE_WORLD_HEIGHT = BASE_WORLD_WIDTH * (TEXTURE_HEIGHT / TEXTURE_WIDTH)

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
-- muted, premium, renderTarget, dirty, lastSignature } - afk/muted/premium
-- come from the server the same as role/onDuty now (see
-- NametagService.lua's own module comment on why), so nothing here reads
-- ElementData directly; every field only changes on NAMETAG_DATA_RECEIVED,
-- which is exactly when redrawIfDirty needs to re-render the texture.
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
--- drop shadow - every text line drawn onto a nametag texture uses this
--- same shadow+left-aligned convention, so it's factored out instead of
--- repeated per line.
local function drawLeftText(text, x, y, scale, textFont, color, alpha)
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, alpha), scale, textFont, "left", "center", false, false, false, true)
    dxDrawText(text, x, y, x, y, tocolor(color[1], color[2], color[3], alpha), scale, textFont, "left", "center", false, false, false, true)
end

--- @param player element
-- @return string a signature string that changes iff anything drawTexture
--         would actually draw differently changes - compared against
--         entry.lastSignature to decide whether a redraw is needed.
local function signatureOf(entry)
    return table.concat({
        entry.id, entry.name, tostring(entry.role), tostring(entry.onDuty),
        entry.color and table.concat(entry.color, ",") or "nil",
        tostring(entry.afk), tostring(entry.muted), tostring(entry.premium),
        tostring(entry.level),
    }, "|")
end

--- Draws one player's full nametag layout onto their own render target,
--- at a fixed TEXTURE_WIDTH x TEXTURE_HEIGHT resolution (opaque alpha -
--- distance fade is applied later, per-frame, via dxDrawImage3D's own
--- color argument on the cached texture, not baked into the texture
--- itself). Only called from redrawIfDirty, never every frame.
-- @param entry table one streamedPlayers[player] entry
local function drawTexture(entry)
    dxSetRenderTarget(entry.renderTarget, true)

    local scale = 1
    local alpha = 255

    local dutyColor = entry.onDuty and entry.color or DEFAULT_COLOR
    local roleName = entry.onDuty and ROLE_DISPLAY_NAME[entry.role] or nil

    local statusIcons = {}
    if entry.afk then
        statusIcons[#statusIcons + 1] = { key = "afk", color = AFK_COLOR }
    end
    if entry.muted then
        statusIcons[#statusIcons + 1] = { key = "mute", color = MUTE_COLOR }
    end
    if entry.premium then
        statusIcons[#statusIcons + 1] = { key = "premium", color = PREMIUM_COLOR }
    end

    -- Anchored to the texture's own bottom edge (TEXTURE_HEIGHT), not
    -- vertically centered in it - worldSizeFor/renderNametags position
    -- the billboard so this bottom edge sits just above the player's
    -- head, with any unused space above (status icon row, when present)
    -- extending upward within the same fixed-size texture.
    local blockCenterY = TEXTURE_HEIGHT - 40
    local idIconSize = 88
    local textGap = 8
    local nameScale = roleName and scale * 1.6 or scale * 2.2
    local nameText = entry.name
    local nameWidth = dxGetTextWidth(nameText, nameScale, roleName and font or fontBold)
    local blockWidth = idIconSize + textGap + nameWidth
    local leftX = TEXTURE_WIDTH / 2 - blockWidth / 2

    if #statusIcons > 0 then
        local iconSize = 56
        local iconGap = -6
        local iconY = blockCenterY - idIconSize / 2 - iconSize - 6
        local iconX = leftX + 4

        for _, icon in ipairs(statusIcons) do
            dxDrawImage(iconX, iconY, iconSize, iconSize, iconsTextures[icon.key], 0, 0, 0, tocolor(icon.color[1], icon.color[2], icon.color[3], alpha))
            iconX = iconX + iconSize + iconGap
        end
    end

    local idIconY = blockCenterY - idIconSize / 2
    dxDrawImage(leftX, idIconY, idIconSize, idIconSize, iconsTextures.id, 0, 0, 0, tocolor(dutyColor[1], dutyColor[2], dutyColor[3], alpha))
    -- White with a black shadow (same convention as every other text
    -- here) rather than a fixed black - id.png is tinted to dutyColor
    -- above, which can itself be dark (e.g. ADMINISTRATOR's red), so
    -- plain black text would go unreadable against it.
    local idText = tostring(entry.id)
    dxDrawText(idText, leftX + 1, idIconY + 1, leftX + idIconSize + 1, idIconY + idIconSize + 1, tocolor(0, 0, 0, alpha), scale * 1.4, fontBold, "center", "center")
    dxDrawText(idText, leftX, idIconY, leftX + idIconSize, idIconY + idIconSize, tocolor(255, 255, 255, alpha), scale * 1.4, fontBold, "center", "center")

    local textX = leftX + idIconSize + textGap

    if roleName then
        local nameY = blockCenterY - 16
        local roleY = blockCenterY + 16
        drawLeftText(nameText, textX, nameY, nameScale, fontBold, DEFAULT_COLOR, alpha)
        drawLeftText(roleName, textX, roleY, scale * 1.35, fontBold, entry.color, alpha)
    else
        drawLeftText(nameText, textX, blockCenterY, nameScale, fontBold, DEFAULT_COLOR, alpha)
    end

    dxSetRenderTarget()
end

--- Re-renders `entry`'s texture if (and only if) its data changed since
--- the last render, or it doesn't have a texture yet (fresh nametag, or
--- one lost to onClientRestore clearing every render target - see that
--- handler's own comment).
-- @param player element
-- @param entry table
local function redrawIfDirty(player, entry)
    local signature = signatureOf(entry)
    if entry.renderTarget and isElement(entry.renderTarget) and signature == entry.lastSignature then
        return
    end

    if not entry.renderTarget or not isElement(entry.renderTarget) then
        entry.renderTarget = dxCreateRenderTarget(TEXTURE_WIDTH, TEXTURE_HEIGHT, true)
        if not entry.renderTarget then
            -- Creation can fail under video-memory pressure (see
            -- https://wiki.multitheftauto.com/wiki/DxCreateRenderTarget) -
            -- leave lastSignature unset so the next redrawIfDirty call
            -- retries instead of silently giving up on this player forever.
            return
        end
    end

    drawTexture(entry)
    entry.lastSignature = signature
end

--- @param distance number
-- @return number, number world-space width, height for dxDrawImage3D at
--         this distance - the 3D-billboard equivalent of the old 2D
--         code's textScale = math.max(0.45, 0.75 - distance*0.02): closer
--         means visually larger, distance beyond DRAW_DISTANCE is never
--         reached since renderNametags already gates on that.
local function worldSizeFor(distance)
    local scale = math.max(0.45, 0.75 - distance * 0.02) / 0.75
    return BASE_WORLD_WIDTH * scale, BASE_WORLD_HEIGHT * scale
end

local function renderNametags()
    local cx, cy, cz = getCameraMatrix()

    for player, entry in pairs(streamedPlayers) do
        if isElement(player) then
            local px, py, pz = getPedBonePosition(player, HEAD_BONE_ID)
            local distance = getDistanceBetweenPoints3D(cx, cy, cz, px, py, pz)

            if distance < DRAW_DISTANCE and isLineOfSightClear(cx, cy, cz, px, py, pz, true, false, false, true, false, false, true, nil) then
                redrawIfDirty(player, entry)

                if entry.renderTarget and isElement(entry.renderTarget) then
                    local progress = (distance - FADE_DISTANCE) / (DRAW_DISTANCE - FADE_DISTANCE)
                    local alpha = math.max(0, math.min(BASE_ALPHA - (BASE_ALPHA * progress), BASE_ALPHA)) * (getElementAlpha(player) / 255)
                    local worldWidth, worldHeight = worldSizeFor(distance)

                    -- dxDrawImage3D doesn't exist on this MTA version
                    -- ("attempt to call global 'dxDrawImage3D' (a nil
                    -- value)", confirmed live) despite being wiki-
                    -- documented - it's only a thin wrapper around
                    -- dxDrawMaterialLine3D anyway (see this file's own
                    -- module comment), so the billboard is built from
                    -- that directly instead: a perfectly VERTICAL line
                    -- (same x/y, bottom -> top z) with faceTowardX/Y/Z set
                    -- to the camera position - MTA then draws the line's
                    -- own `width` extending horizontally, perpendicular to
                    -- both the vertical line and the camera direction,
                    -- which is exactly a camera-facing vertical quad (the
                    -- same technique [custom]/markers/client/material.lua's
                    -- own drawTransformedMaterial already uses in this
                    -- project, just with the camera itself as the face-
                    -- toward point instead of a fixed direction vector).
                    -- Anchored so the texture's own bottom edge (see
                    -- drawTexture's own comment on blockCenterY) sits at
                    -- pz + 0.35 (just above the head bone), extending
                    -- upward - not centered on that point.
                    local bottomZ = pz + 0.35
                    local topZ = bottomZ + worldHeight
                    -- flipUV=false and stage=false (both positional,
                    -- before material and before faceToward respectively)
                    -- match [custom]/markers/client/material.lua's own
                    -- drawTransformedMaterial call - the exact same
                    -- dxDrawMaterialLine3D argument order already
                    -- established elsewhere in this project.
                    --
                    -- start/end run top->bottom (topZ first, bottomZ
                    -- second), not bottom->top - confirmed live that
                    -- bottom->top rendered the texture upside down (MTA
                    -- maps the texture's V axis along start->end, so the
                    -- texture's own top row - which drawTexture always
                    -- draws first, at y=0 - needs to line up with
                    -- whichever endpoint comes FIRST here).
                    -- faceToward uses the camera's X/Y but the BILLBOARD'S
                    -- OWN Z, not the camera's real Z - a perfectly
                    -- vertical line's own "face toward" direction is
                    -- normally derived by projecting the target point
                    -- onto the plane perpendicular to the line, but when
                    -- the camera is nearly straight above/below the
                    -- billboard (looking steeply up or down), the real
                    -- camera position and the vertical line become
                    -- near-collinear, which degenerates the billboard's
                    -- orientation (confirmed live: aiming the camera
                    -- upward made it stop facing the camera correctly).
                    -- Flattening faceToward's Z to the line's own
                    -- mid-height keeps the face-toward vector always
                    -- horizontal relative to the line, so it only ever
                    -- yaws to face the camera left/right and never
                    -- degenerates from a steep vertical viewing angle -
                    -- the standard "Y-axis-locked billboard" technique.
                    dxDrawMaterialLine3D(
                        px, py, topZ,
                        px, py, bottomZ,
                        false,
                        entry.renderTarget,
                        worldWidth,
                        tocolor(255, 255, 255, alpha),
                        false,
                        cx, cy, (topZ + bottomZ) / 2
                    )
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
        renderTarget = nil,
        lastSignature = nil,
    }
    requestNametagData(player)

    if not renderHandlerAttached then
        addEventHandler("onClientRender", root, renderNametags)
        renderHandlerAttached = true
    end
end

--- @param player element
local function removeNametag(player)
    local entry = streamedPlayers[player]
    if not entry then
        return
    end

    if entry.renderTarget and isElement(entry.renderTarget) then
        destroyElement(entry.renderTarget)
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
    -- Actual re-render happens lazily in redrawIfDirty (called from
    -- renderNametags) rather than here - this handler may fire for a
    -- player who isn't even currently on-screen/in DRAW_DISTANCE.
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

-- Render targets are cleared on alt-tab/minimize (see
-- https://wiki.multitheftauto.com/wiki/DxCreateRenderTarget's own note on
-- this) - forcing every entry's lastSignature to nil makes the next
-- redrawIfDirty call for each visible nametag redraw it from scratch
-- instead of continuing to display a now-blank texture.
addEventHandler("onClientRestore", root, function()
    for _, entry in pairs(streamedPlayers) do
        entry.lastSignature = nil
    end
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

    for _, entry in pairs(streamedPlayers) do
        if entry.renderTarget and isElement(entry.renderTarget) then
            destroyElement(entry.renderTarget)
        end
    end
    streamedPlayers = {}

    for k, v in pairs(iconsTextures) do
        if isElement(v) then
            destroyElement(v)
        end
        iconsTextures[k] = nil
    end
    iconsTextures = {}
end)
