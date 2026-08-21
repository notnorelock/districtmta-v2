-- Loads a player's own items once their account context resolves (a
-- fresh login) - see ItemService.lua's own module comment on why items
-- live in a server-only table rather than element data.
addEvent(Events.PLAYER_ACCOUNT_RESOLVED, true)
addEventHandler(Events.PLAYER_ACCOUNT_RESOLVED, root, function(account)
    if type(account) ~= "table" or type(account.id) ~= "number" then
        return
    end
    ItemService.load(source, account.id)
end)

-- PLAYER_ACCOUNT_RESOLVED only fires for a genuinely fresh login -
-- PlayerService.restoreAccountContextSilently (an already-spawned
-- player, `core` itself restarting mid-session) deliberately does NOT
-- fire it (see PlayerService.lua's own module comment on why). That's
-- fine for `core` restarting - this resource's own playerItems table
-- survives a `core`-only restart untouched. But if THIS resource
-- restarts instead (not `core`), playerItems is wiped by the restart
-- itself and no PLAYER_ACCOUNT_RESOLVED will ever fire again for anyone
-- already connected - so on start, every already-authenticated player
-- gets their items loaded directly here, the same "resource restart
-- reconnect" gap PlayerService.lua's own reconnectAlreadyLoggedInPlayers
-- closes for account contexts.
local function loadAlreadyConnectedPlayers()
    for _, player in ipairs(getElementsByType("player")) do
        local ok, accountId = pcall(PlayerService.getAccountId, player)
        if ok and accountId then
            ItemService.load(player, accountId)
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Same DATABASE_READY/Schema.isMigrated() gotcha ItemService.lua's
    -- own onResourceStart handles for world items - core (started
    -- earlier in core_bootstrap's chain) may still be mid-migration when
    -- THIS resource's onResourceStart fires.
    local migratedOk, migrated = pcall(function() return exports.core:schemaIsMigrated() end)
    if migratedOk and migrated then
        loadAlreadyConnectedPlayers()
    else
        addEvent(Events.DATABASE_READY, true)
        addEventHandler(Events.DATABASE_READY, root, loadAlreadyConnectedPlayers)
    end
end)
