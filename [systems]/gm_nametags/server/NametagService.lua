-- Answers a client's per-player nametag data request (role/duty/afk/
-- muted/premium/level) - role and duty are server-only CONCEPTS
-- (PlayerService.lua/Permissions.lua have no client export chain, see
-- GlobalResources.lua's own comment), so the client genuinely can't
-- derive them itself. afk/muted/premium are technically plain element
-- data a client could read directly off the player element (the same way
-- it already reads ElementData.Player.ID) - they're still routed through
-- here anyway rather than read client-side, to keep every piece of
-- nametag data server-authoritative through one single channel instead
-- of splitting trust between "some fields come from the server, some the
-- client reads itself". No level/xp system exists in this project yet
-- (see ItemSchemes.lua's/ui_hud's own "no backing system yet" precedent
-- for PLACEHOLDER_HUNGER/THIRST) - `level` is a flat placeholder constant
-- here for the same reason, wired up once such a system exists.
NametagService = NametagService or {}

local PLACEHOLDER_LEVEL = 1
-- How often every connected player's own nametag data is re-reported to
-- whoever can currently see them - a request/response pair fired only
-- once at stream-in (the original approach) never notices something
-- changing WHILE already streamed in for other clients (duty toggled, a
-- mute landing, premium expiring, ...) - their nametag would keep showing
-- stale data until they happened to stream out and back in. A periodic
-- report keeps every visible nametag current instead.
local REPORT_INTERVAL_MS = 1000
-- Matches NametagState.lua's own DRAW_DISTANCE - no point reporting a
-- subject's data to a viewer whose client wouldn't even be drawing their
-- nametag at that range.
local REPORT_RANGE = 40

local GROUP_DUTY_COLOR_BY_TYPE = {
    gang = "#e74c3c",
    organization = "#3498db",
    fraction = "#f2b84a",
}

--- @param player element
-- @return table|nil { groupName, groupType, rankName, color } if
--         currently on GROUP duty (gm_groups/server/GroupDutyService.lua's
--         own ElementData.Player.GROUP_DUTY, a { group = { id, name,
--         type }, rank = { id, name } } table), nil otherwise. Flattened
--         here (not passed through as-is) since NametagState.lua's own
--         subLabelOf/drawNametag only ever need these four scalars.
local function groupDutyDataFor(player)
    local groupDuty = getElementData(player, ElementData.Player.GROUP_DUTY)
    if type(groupDuty) ~= "table" or type(groupDuty.group) ~= "table" or type(groupDuty.rank) ~= "table" then
        return nil
    end

    return {
        groupName = groupDuty.group.name,
        groupType = groupDuty.group.type,
        rankName = groupDuty.rank.name,
        color = GROUP_DUTY_COLOR_BY_TYPE[groupDuty.group.type] or GROUP_DUTY_COLOR_BY_TYPE.organization,
    }
end

--- @param player element
-- @return table { role, onDuty, color, afk, muted, premium, level, groupDuty }
local function nametagDataFor(player)
    local role = PlayerService.getRole(player)
    local onDuty = PlayerService.isOnDuty(player)

    return {
        role = role,
        onDuty = onDuty,
        color = onDuty and Permissions.colorForRole(role) or nil,
        afk = getElementData(player, ElementData.Player.AFK) == true,
        muted = type(getElementData(player, ElementData.Account.MUTE)) == "table",
        premium = getElementData(player, ElementData.Account.PREMIUM) == true,
        level = PLACEHOLDER_LEVEL,
        groupDuty = groupDutyDataFor(player),
    }
end

--- Reports every connected player's own current nametag data, but only
--- to the other players actually within REPORT_RANGE of them right now -
--- broadcasting every subject's data to every client regardless of
--- distance would scale O(playerCount^2) in both directions for no
--- reason (a viewer 200m away from someone can't see their nametag at
--- all, so has no use for their duty/afk/mute/premium status either).
local function reportAllPlayers()
    local spawnedPlayers = {}
    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, ElementData.Player.SPAWNED) == true then
            spawnedPlayers[#spawnedPlayers + 1] = player
        end
    end

    for _, subject in ipairs(spawnedPlayers) do
        local data = nametagDataFor(subject)
        local sx, sy, sz = getElementPosition(subject)

        for _, viewer in ipairs(spawnedPlayers) do
            -- if viewer ~= subject then
                local vx, vy, vz = getElementPosition(viewer)
                if getDistanceBetweenPoints3D(sx, sy, sz, vx, vy, vz) <= REPORT_RANGE then
                    triggerClientEvent(viewer, Events.NAMETAG_DATA_RECEIVED, resourceRoot, subject, data)
                end
            -- end
        end
    end
end

-- Also disables MTA's own built-in nametag for every connected player -
-- this resource replaces it entirely with its own dx-drawn version
-- (NametagState.lua), so the default floating name/health bar must never
-- render alongside it.
local function hideDefaultNametags()
    for _, player in ipairs(getElementsByType("player")) do
        setPlayerNametagShowing(player, false)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    hideDefaultNametags()
    setTimer(reportAllPlayers, REPORT_INTERVAL_MS, 0)
end)

addEventHandler("onPlayerJoin", root, function()
    setPlayerNametagShowing(source, false)
end)

-- Still answered on-demand for the immediate stream-in case (so a
-- newly-visible nametag doesn't sit at its "?"/no-color placeholder for
-- up to REPORT_INTERVAL_MS before the next periodic broadcast reaches it).
addEvent(Events.NAMETAG_REQUEST_DATA, true)
addEventHandler(Events.NAMETAG_REQUEST_DATA, root, function(player)
    if not isElement(player) or getElementType(player) ~= "player" then
        return
    end

    triggerClientEvent(client, Events.NAMETAG_DATA_RECEIVED, resourceRoot, player, nametagDataFor(player))
end)
