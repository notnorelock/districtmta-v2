-- Scoreboard (TAB): builds the connected-player list on request. Request/
-- response rather than a periodic push (see Events.lua's own comment on
-- SCOREBOARD_REQUEST_PLAYERS) - the client asks fresh every time the
-- overlay is opened (TAB-down), so there's no need to keep broadcasting
-- to players who aren't currently looking at it.
ScoreboardService = ScoreboardService or {}

-- Status ordering mirrors the actual auth/loading pipeline (core_loading ->
-- core_auth -> spawn selection -> gameplay) - see docs/Architecture.md's
-- "Loading gate" section. Every connected player is in exactly one of
-- these at any time; there's no "disconnected" entry since a quit player
-- is simply absent from getElementsByType("player").
ScoreboardService.Status = {
    DOWNLOADING = "downloading",
    AUTHENTICATING = "authenticating",
    SELECTING_SPAWN = "selectingSpawn",
    IN_GAME = "inGame",
}

--- @param player element
-- @return string one of ScoreboardService.Status
local function statusOf(player)
    if getElementData(player, ElementData.Player.LOADING_READY) ~= true then
        return ScoreboardService.Status.DOWNLOADING
    end

    local ok, authenticated = pcall(function()
        return exports.core:playerServiceIsAuthenticated(player)
    end)
    if not ok or not authenticated then
        return ScoreboardService.Status.AUTHENTICATING
    end

    if getElementData(player, ElementData.Player.SPAWNED) ~= true then
        return ScoreboardService.Status.SELECTING_SPAWN
    end

    return ScoreboardService.Status.IN_GAME
end

--- @param player element
-- @return boolean true only if the player is actually ON DUTY right now -
--         mirrors PlayerService.isOnDuty's own presence check
--         (ElementData.Player.ADMIN holds a { role, dutySince } table
--         while on duty, is absent otherwise). A high account role alone
--         (e.g. an off-duty Administrator) must NOT show as staff here -
--         same reasoning PlayerService already applies to nametag color.
local function isOnDuty(player)
    return type(getElementData(player, ElementData.Player.ADMIN)) == "table"
end

--- @param player element
-- @return table plain-data entry for the CEF scoreboard - login/role are
--         nil (become false, see uiPushEvent's own nil-handling comment
--         elsewhere in this project) until the player has actually
--         authenticated, since neither exists before then. role is ALSO
--         nil while authenticated but off duty - see isOnDuty above.
local function toEntry(player)
    local ok, login = pcall(function()
        return exports.core:playerServiceGetLogin(player)
    end)

    local role = nil
    if isOnDuty(player) then
        local roleOk, roleValue = pcall(function()
            return exports.core:playerServiceGetRole(player)
        end)
        role = roleOk and roleValue or nil
    end

    return {
        id = getElementData(player, ElementData.Player.ID) or 0,
        name = getPlayerName(player),
        login = (ok and login) or nil,
        role = role,
        -- No faction/group system exists yet in this project (see
        -- gm_blackout/server/BlackoutService.lua's own TODO on the same
        -- gap) - nil today, a placeholder column on the frontend until
        -- one exists to actually populate it.
        faction = nil,
        status = statusOf(player),
        ping = getPlayerPing(player),
    }
end

--- @return table[] one entry per connected player, in no particular order
--         (the frontend sorts/filters client-side).
ScoreboardService.getPlayers = function()
    local entries = {}
    for _, player in ipairs(getElementsByType("player")) do
        entries[#entries + 1] = toEntry(player)
    end
    return entries
end

addEvent(Events.SCOREBOARD_REQUEST_PLAYERS, true)
addEventHandler(Events.SCOREBOARD_REQUEST_PLAYERS, root, function()
    -- Server-authoritative mirror of ScoreboardState.lua's own spawned
    -- check - that client-side gate only stops the request from ever
    -- being sent under normal play, it doesn't stop a modified client
    -- from sending it anyway.
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end

    triggerClientEvent(client, Events.SCOREBOARD_PLAYERS_RECEIVED, client, ScoreboardService.getPlayers())
end)
