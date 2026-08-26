-- Server-side half of "tell the client to open/close the auth UI window" -
-- see docs/Architecture.md's account lifecycle section, including the
-- full-chain-restart gap reopenSpawnSelectForUnspawnedPlayers closes.

local IGNORE_KEYS = {
    ["email"] = true,
    ["login"] = true,
    ["money"] = true,
    ["mta_serial"] = true,
    ["created_at"] = true,
    ["updated_at"] = true,
    ["last_seen_at"] = true,
    ["password_hash"] = true,
    ["two_factor_secret"] = true,
    ["premium_expires_at"] = true,
    ["two_factor_enabled_at"] = true,
}

local function setupPlayerData(player, data)
    if not player or not isElement(player) then
        return
    end

    setElementData(player, ElementData.Player.LOGGED, true)

    for k, v in pairs(data) do
        if not IGNORE_KEYS[k] then
            setElementData(player, ElementData.accountField(k), v)
        end
    end
end

addEventHandler(Events.PLAYER_ACCOUNT_RESOLVED, root, function(account)
    local player = source

    setupPlayerData(player, account)
    triggerClientEvent(player, Events.AUTH_SUCCESS_AUTHENTICATION, player)
    triggerClientEvent(player, Events.SPAWN_SELECT_OPEN, player)
end)

addEventHandler(Events.LOADING_READY, root, function()
    local player = source

    local logged = getElementData(player, ElementData.Player.LOGGED)
    local authenticated = PlayerService.isAuthenticated(player)

    if not logged or not authenticated then
        triggerClientEvent(player, Events.AUTH_BEGIN_AUTHENTICATION, player)
        return
    end

    -- Logged in AND authenticated - if also already spawned, this is a
    -- mid-session resource restart (CEF remounted, nothing to open):
    -- reopenSpawnSelectForUnspawnedPlayers below already covers "logged
    -- in but not yet spawned" by reopening spawn-select, so this is the
    -- one remaining case neither branch handled - see Events.
    -- AUTH_ALREADY_IN_WORLD's own comment.
    if getElementData(player, ElementData.Player.SPAWNED) == true then
        triggerClientEvent(player, Events.AUTH_ALREADY_IN_WORLD, player)
    end
end)

local function reopenSpawnSelectForUnspawnedPlayers()
    for _, player in ipairs(getElementsByType("player")) do
        local logged = getElementData(player, ElementData.Player.LOGGED)
        local authenticated = PlayerService.isAuthenticated(player)
        local spawned = getElementData(player, ElementData.Player.SPAWNED)
        if logged and authenticated and spawned ~= true then
            triggerClientEvent(player, Events.SPAWN_SELECT_OPEN, player)
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, reopenSpawnSelectForUnspawnedPlayers)
