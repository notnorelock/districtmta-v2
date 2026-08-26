-- Runtime cache of each connected player's resolved account (login-scoped,
-- cleared on quit). Does not survive a `core` resource restart on its own;
-- reconnectAlreadyLoggedInPlayers() below restores it from element data.
PlayerService = PlayerService or {}

-- player -> { id, serial, login, email, createdAt, updatedAt, lastSeenAt }
local accountContexts = {}

addEvent(Events.PLAYER_ACCOUNT_RESOLVED, true)
addEvent(Events.PLAYER_ACCOUNT_CLEARED, true)
addEvent(Events.PLAYER_PREMIUM_EXPIRED, true)

local PREMIUM_SWEEP_INTERVAL_MS = 5 * 60 * 1000
local MUTE_SWEEP_INTERVAL_MS = 30 * 1000

--- @param mute table an account_penalties row (see AccountPenalty.lua)
-- @return table plain-data subset safe to hand to setElementData -
--         id/reason/expiresAt/createdAt only, never the full row (no
--         mta_serial/issued_by_account_id - internal/audit-only fields
--         with no reason to be readable by every resource)
local function toMuteElementData(mute)
    return {
        id = mute.id,
        reason = mute.reason,
        expiresAt = mute.expires_at,
        createdAt = mute.created_at,
    }
end

local DEFAULT_NAMETAG_COLOR = { 255, 255, 255 }
local PREMIUM_NAMETAG_COLOR = { 227, 176, 23 } -- #e3b017, same gold Chat.lua used to hardcode

--- @param hex string "#RRGGBB"
-- @return number, number, number r, g, b (0-255 each)
local function hexToRgb(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- Recomputes and caches `player`'s chat-name color. Precedence: on-duty
--- role color wins, else premium gold, else white. Call whenever an input
--- changes (login, duty toggle, premium grant/expiry) - not per chat message.
-- @param player element
PlayerService.refreshNametagColor = function(player)
    if not isElement(player) then
        return
    end

    local color = DEFAULT_NAMETAG_COLOR

    if type(getElementData(player, ElementData.Player.ADMIN)) == "table" then
        local roleColor = Permissions.colorForRole(playerServiceGetRole(player))
        if roleColor then
            color = { hexToRgb(roleColor) }
        end
    end

    if color == DEFAULT_NAMETAG_COLOR and getElementData(player, ElementData.Account.PREMIUM) == true then
        color = PREMIUM_NAMETAG_COLOR
    end

    setPlayerNametagColor(player, color[1], color[2], color[3])
end

--- Establishes the authenticated account context for a player.
-- @param player element
-- @param account table full account record (server-internal shape)
PlayerService.setAccountContext = function(player, account)
    assert(isElement(player), "PlayerService.setAccountContext expects a player element")
    assert(type(account) == "table", "PlayerService.setAccountContext expects an account table")

    accountContexts[player] = account

    Logger.info("PlayerService", "Account context established", {
        player = getPlayerName(player),
        accountId = account.id,
    })

    if AccountService.isPremiumActive(account) then
        outputChatBox(
            ("Twoje konto ma aktywne premium do %s."):format(
                AccountService.formatExpiryForDisplay(account.premium_expires_at)
            ),
            player, 255, 215, 0
        )

        setElementData(player, ElementData.Account.PREMIUM, true)
    end

    if getPlayerName(player) ~= account.login then
        setPlayerName(player, account.login)
    end
    PlayerService.refreshNametagColor(player)

    AccountPenaltyService.isMuted(account.id, function(isMuted, activeMute)
        if isMuted and isElement(player) and accountContexts[player] == account then
            setElementData(player, ElementData.Account.MUTE, toMuteElementData(activeMute))
        end
    end, function(message)
        Logger.error("PlayerService", "isMuted check failed on login", {
            player = getPlayerName(player),
            accountId = account.id,
            error = message,
        })
    end)

    triggerEvent(Events.PLAYER_ACCOUNT_RESOLVED, player, account)
end

--- Same as setAccountContext, but does NOT fire Events.PLAYER_ACCOUNT_RESOLVED
--- - used for a player who was already spawned before this resource
--- restarted, so core_auth/gm_roleplay don't re-run login/spawn flow for them.
-- @param player element
-- @param account table full account record (server-internal shape)
PlayerService.restoreAccountContextSilently = function(player, account)
    assert(isElement(player), "PlayerService.restoreAccountContextSilently expects a player element")
    assert(type(account) == "table", "PlayerService.restoreAccountContextSilently expects an account table")

    accountContexts[player] = account

    Logger.info("PlayerService", "Account context silently restored (already-spawned player, resource restart)", {
        player = getPlayerName(player),
        accountId = account.id,
    })
end

--- Clears the account context for a player (called on quit, or explicit logout later).
-- @param player element
PlayerService.clearAccountContext = function(player)
    if accountContexts[player] then
        accountContexts[player] = nil
        triggerEvent(Events.PLAYER_ACCOUNT_CLEARED, player)
    end
end

--- Returns the full account context table, or nil if not authenticated.
-- @param player element
PlayerService.getAccount = function(player)
    return accountContexts[player]
end

--- Returns just the account id, or nil if not authenticated.
-- @param player element
PlayerService.getAccountId = function(player)
    local account = accountContexts[player]
    return account and account.id or nil
end

--- @param player element
-- @return boolean
PlayerService.isAuthenticated = function(player)
    return accountContexts[player] ~= nil
end

--- @param player element
-- @return number|nil the account's own money balance, or nil if not authenticated
PlayerService.getMoney = function(player)
    local account = accountContexts[player]
    return account and account.money or nil
end

--- Adds to the player's account money balance (atomic UPDATE, see
-- AccountRepository.giveMoney) and mirrors the new total onto the
-- cached account context so a subsequent PlayerService.getMoney call in
-- the same session reads the up-to-date value without a re-fetch.
-- @param player element
-- @param amount number positive integer
-- @param callback function(ok: boolean)|nil
PlayerService.giveMoney = function(player, amount, callback)
    local account = accountContexts[player]
    if not account or type(amount) ~= "number" or amount <= 0 then
        if callback then callback(false) end
        return
    end

    AccountRepository.giveMoney(account.id, math.floor(amount), function(ok, affectedOrError)
        if ok and accountContexts[player] == account then
            account.money = (account.money or 0) + math.floor(amount)
        elseif not ok then
            Logger.error("PlayerService", "giveMoney failed", { player = getPlayerName(player), accountId = account.id, error = tostring(affectedOrError) })
        end
        if callback then callback(ok) end
    end)
end

--- Same as giveMoney, subtracting instead - floored at 0 server-side (see
-- AccountRepository.takeMoney), so the cached mirror is clamped the same way.
-- @param player element
-- @param amount number positive integer
-- @param callback function(ok: boolean)|nil
PlayerService.takeMoney = function(player, amount, callback)
    local account = accountContexts[player]
    if not account or type(amount) ~= "number" or amount <= 0 then
        if callback then callback(false) end
        return
    end

    AccountRepository.takeMoney(account.id, math.floor(amount), function(ok, affectedOrError)
        if ok and accountContexts[player] == account then
            account.money = math.max(0, (account.money or 0) - math.floor(amount))
        elseif not ok then
            Logger.error("PlayerService", "takeMoney failed", { player = getPlayerName(player), accountId = account.id, error = tostring(affectedOrError) })
        end
        if callback then callback(ok) end
    end)
end

addEventHandler("onPlayerQuit", root, function()
    PlayerService.clearAccountContext(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        PlayerService.clearAccountContext(player)
    end
end)

--- Re-establishes accountContexts for players already logged in before this
--- resource restarted. Branches on player:spawned: already-spawned players
--- are restored silently (no PLAYER_ACCOUNT_RESOLVED, to avoid re-running
--- spawn flow); not-yet-spawned players go through the normal resolve path.
local function reconnectAlreadyLoggedInPlayers()
    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, ElementData.Player.LOGGED) == true and not PlayerService.isAuthenticated(player) then
            local accountId = getElementData(player, ElementData.accountField("id"))

            if type(accountId) ~= "number" then
                Logger.warn("PlayerService", "player:logged set but account:id missing/invalid - skipping reconnect", {
                    player = getPlayerName(player),
                })
            -- Deliberately manual, not canPlayerInteract - this is a
            -- 3-way branch selector (skip/silently-restore/full-resolve),
            -- not a boolean interaction guard.
            elseif getElementData(player, ElementData.Player.SPAWNED) == true then
                AccountRepository.findById(accountId, function(ok, account)
                    if not ok or not account then
                        Logger.error("PlayerService", "Failed to silently restore already-spawned player's account context", {
                            player = getPlayerName(player),
                            accountId = accountId,
                            error = tostring(account),
                        })
                        return
                    end

                    PlayerService.restoreAccountContextSilently(player, account)
                end)
            else
                AccountService.resolveForPlayer(player, accountId, function(account)
                    Logger.info("PlayerService", "Reconnected already-logged-in player after resource restart", {
                        player = getPlayerName(player),
                        accountId = account.id,
                    })
                end, function(code, message)
                    Logger.error("PlayerService", "Failed to reconnect already-logged-in player", {
                        player = getPlayerName(player),
                        code = code,
                        message = message,
                    })
                end)
            end
        end
    end
end

-- Waits for Events.DATABASE_READY rather than plain onResourceStart, since
-- this queries `accounts` before Schema.migrate is guaranteed done.
if Schema.isMigrated() then
    reconnectAlreadyLoggedInPlayers()
else
    addEventHandler(Events.DATABASE_READY, resourceRoot, reconnectAlreadyLoggedInPlayers)
end

-- player:admin element data lives on the player element, so it survives a
-- `core`-only restart even though duty should not. Force it off for
-- everyone connected on start so isOnDuty/`/duty` don't get stuck inverted.
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if PlayerService.isOnDuty(player) then
            PlayerService.setDuty(player, false)
        end
    end
end)

-- Re-checks every logged-in player's premium expiry and revokes a lapsed
-- one mid-session (login only clears it once, at resolve time).
local function sweepExpiredPremium()
    for player, account in pairs(accountContexts) do
        if getElementData(player, ElementData.Account.PREMIUM) == true then
            AccountRepository.findById(account.id, function(ok, freshAccount)
                if not ok or not freshAccount then
                    Logger.error("PlayerService", "Premium sweep: failed to re-check account", {
                        player = isElement(player) and getPlayerName(player) or "?",
                        accountId = account.id,
                        error = tostring(freshAccount),
                    })
                    return
                end

                if not isElement(player) or not accountContexts[player] then
                    return
                end

                accountContexts[player].premium_expires_at = freshAccount.premium_expires_at

                if not AccountService.isPremiumActive(freshAccount) then
                    removeElementData(player, ElementData.Account.PREMIUM)
                    accountContexts[player].premium_expires_at = nil

                    if type(freshAccount.premium_expires_at) == "string" then
                        AccountRepository.clearExpiredPremium(account.id, function() end)
                    end

                    outputChatBox("Twoje konto premium wygaslo.", player, 255, 215, 0)

                    Logger.info("PlayerService", "Premium expired mid-session, revoked", {
                        player = getPlayerName(player),
                        accountId = account.id,
                    })

                    PlayerService.refreshNametagColor(player)
                    triggerEvent(Events.PLAYER_PREMIUM_EXPIRED, player)
                end
            end)
        end
    end
end

-- Self-rescheduling rather than a repeating setTimer, so a slow sweep can't
-- overlap with the next one.
local function schedulePremiumSweep()
    setTimer(function()
        sweepExpiredPremium()
        schedulePremiumSweep()
    end, PREMIUM_SWEEP_INTERVAL_MS, 1)
end

addEventHandler("onResourceStart", resourceRoot, schedulePremiumSweep)

-- Re-checks every logged-in player's mute status and mirrors it onto
-- account:mute element data (read synchronously by Chat.lua). Goes both
-- ways: sets it for a freshly-muted player, clears it once expired/revoked.
local function sweepMuteStatus()
    for player, account in pairs(accountContexts) do
        AccountPenaltyService.isMuted(account.id, function(isMuted, activeMute)
            if not isElement(player) or not accountContexts[player] then
                return
            end

            if isMuted then
                setElementData(player, ElementData.Account.MUTE, toMuteElementData(activeMute))
            elseif type(getElementData(player, ElementData.Account.MUTE)) == "table" then
                removeElementData(player, ElementData.Account.MUTE)
            end
        end, function(message)
            Logger.error("PlayerService", "Mute sweep: failed to re-check account", {
                player = isElement(player) and getPlayerName(player) or "?",
                accountId = account.id,
                error = message,
            })
        end)
    end
end

local function scheduleMuteSweep()
    setTimer(function()
        sweepMuteStatus()
        scheduleMuteSweep()
    end, MUTE_SWEEP_INTERVAL_MS, 1)
end

addEventHandler("onResourceStart", resourceRoot, scheduleMuteSweep)

function playerServiceIsAuthenticated(player) return PlayerService.isAuthenticated(player) end
function playerServiceGetAccountId(player) return PlayerService.getAccountId(player) end

--- @return number|nil - see PlayerService.getMoney
function playerServiceGetMoney(player) return PlayerService.getMoney(player) end

--- Fire-and-forget flat exports (no callback parameter - a function value
-- can never cross the resource boundary, see docs/Architecture.md's "one
-- hard rule"). A caller in another resource that needs to know whether
-- the transfer actually landed should re-check playerServiceGetMoney
-- shortly after, or (for anything that truly needs a confirmed result)
-- go through a request/response bridge instead, same shape as
-- gm_vehicles/server/VehicleBridge.lua.
function playerServiceGiveMoney(player, amount) PlayerService.giveMoney(player, amount) end
function playerServiceTakeMoney(player, amount) PlayerService.takeMoney(player, amount) end

--- @return string|nil the account login, or nil if not authenticated - a
--- narrow accessor (not the full account context table, which also holds
--- password_hash) for callers outside core that only need the login, e.g.
--- gm_scoreboard's player list.
function playerServiceGetLogin(player)
    local account = PlayerService.getAccount(player)
    return account and account.login or nil
end

-- @return number|nil one of Enums.AccountRole's values, or nil if not authenticated
function playerServiceGetRole(player)
    local account = PlayerService.getAccount(player)
    return account and account.role or nil
end

--- player:admin holds a table ({ role, dutySince }) or is absent - use
--- `type(getElementData(player, ElementData.Player.ADMIN)) == "table"` as the
--- presence check, NOT `~= nil`: MTA's getElementData returns `false`
--- (never real nil) for an unset key, so `~= nil` is always true.
-- @param player element
-- @param onDuty boolean
PlayerService.setDuty = function(player, onDuty)
    assert(isElement(player), "PlayerService.setDuty expects a player element")

    if onDuty then
        setElementData(player, ElementData.Player.ADMIN, {
            role = playerServiceGetRole(player),
            dutySince = os.time(),
        })
    else
        removeElementData(player, ElementData.Player.ADMIN)
    end

    PlayerService.refreshNametagColor(player)
end

--- @param player element
-- @return boolean
PlayerService.isOnDuty = function(player)
    return type(getElementData(player, ElementData.Player.ADMIN)) == "table"
end

addEventHandler("onPlayerChangeNick", root, function(_, _, changedByUser)
    if changedByUser then
        cancelEvent()
        return
    end
end)

addEventHandler("onPlayerQuit", root, function()
    PlayerService.setDuty(source, false)
end)

function playerServiceIsOnDuty(player) return PlayerService.isOnDuty(player) end
