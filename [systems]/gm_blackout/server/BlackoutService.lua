-- Blackout: instead of letting near-fatal damage actually kill a player
-- (MTA's own death/respawn flow), intercept it and put them into a timed,
-- helpless "unconscious" state at low health - a common RP-server pattern
-- (medics reviving downed players, a grace period before "real" death).
-- Server is fully authoritative: the countdown, health floor, and control
-- lockout are all server-driven; the client only renders what the server
-- already decided (see BlackoutState.lua).
BlackoutService = BlackoutService or {}

local BLACKOUT_HP = 5
local BLACKOUT_DURATION_S = 120

--- @param player element
-- @return boolean
BlackoutService.isBlackedOut = function(player)
    return type(getElementData(player, ElementData.Player.BLACKOUT_UNTIL)) == "number"
end

--- @param player element
-- @return number|nil seconds remaining, nil if not blacked out
BlackoutService.secondsRemaining = function(player)
    local until_ = getElementData(player, ElementData.Player.BLACKOUT_UNTIL)
    if type(until_) ~= "number" then
        return nil
    end
    return math.max(0, until_ - os.time())
end

--- Starts blackout for `player`. No-ops if already blacked out - a
--- second near-fatal hit while already down must not restart/extend the
--- clock, or a player could be kept helpless indefinitely by repeated hits.
-- @param player element
-- @param durationSeconds number|nil defaults to BLACKOUT_DURATION_S
BlackoutService.start = function(player, durationSeconds)
    if not isElement(player) or BlackoutService.isBlackedOut(player) then
        return
    end

    local duration = durationSeconds or BLACKOUT_DURATION_S
    local until_ = os.time() + duration
    setElementData(player, ElementData.Player.BLACKOUT_UNTIL, until_)
    setElementData(player, ElementData.Player.BLACKOUT_DURATION, duration)
    setElementHealth(player, BLACKOUT_HP)

    -- TODO: once a faction/group system exists, this is where a medic
    -- callout would be raised, for now blackout only ever ends via its own timer
    -- or an explicit BlackoutService.finish call.

    -- Sends SECONDS REMAINING (computed here, server-side, from os.time()),
    -- not the raw until_ timestamp - the client seeds its own
    -- getTickCount()-based countdown from this value rather than reading
    -- its own (potentially wrong/differently-configured) system clock. Also
    -- sends the total duration this blackout was started with - needed by
    -- the CEF ring so it can normalize progress against the ACTUAL
    -- duration rather than a hardcoded guess, since durationSeconds here
    -- can differ from BLACKOUT_DURATION_S (blackoutServiceStart's own
    -- optional argument). See BlackoutState.lua's own comment on why.
    triggerClientEvent(player, Events.BLACKOUT_STARTED, player, until_ - os.time(), duration)

    if isPedInVehicle(player) then
        removePedFromVehicle(player)
    end

	setTimer(setPedAnimation, 50, 1, player, "ped", "KO_shot_stom", -1, false, true, false, true)

    Logger.info("BlackoutService", "Player entered blackout", { player = getPlayerName(player), until_ = until_ })
end

--- Ends `player`'s blackout early (e.g. a future medic/admin action).
--- No-ops if not currently blacked out.
-- @param player element
BlackoutService.finish = function(player)
    if not isElement(player) or not BlackoutService.isBlackedOut(player) then
        return
    end

    removeElementData(player, ElementData.Player.BLACKOUT_UNTIL)
    removeElementData(player, ElementData.Player.BLACKOUT_DURATION)
    setPedAnimation(player)
    setElementHealth(player, BLACKOUT_HP)
    triggerClientEvent(player, Events.BLACKOUT_ENDED, player)
    Logger.info("BlackoutService", "Player's blackout ended", { player = getPlayerName(player) })
end

--- Revives `player` in place after they died despite being intercepted
--- (see the onPlayerWasted handler below) - MTA's own death makes the ped
--- a ragdoll, so a plain setElementHealth can't undo it; a fresh
--- spawnPlayer at their own last position is the only way back to a
--- controllable, alive ped.
-- @param player element
local function reviveInPlace(player)
    local x, y, z = getElementPosition(player)
    local rotation = getPedRotation(player)

    spawnPlayer(player, x, y, z, rotation, getElementModel(player), getElementInterior(player), getElementDimension(player))
    setElementHealth(player, BLACKOUT_HP)
    fadeCamera(player, true)
    setCameraTarget(player, player)
end

--- Primary interception point: onPlayerDamage fires for damage that does
--- NOT kill the player outright (MTA skips it entirely for fatal damage,
--- firing onPlayerWasted instead - see the fallback handler below), so
--- catching it here means computing whether THIS hit would have been
--- fatal and correcting health before MTA's own death logic ever runs.
addEventHandler("onPlayerDamage", root, function(attacker, damageCausingId, bodypart, loss)
    if BlackoutService.isBlackedOut(source) then
        return
    end
    if getElementData(source, ElementData.Player.SPAWNED) ~= true then
        return
    end

    local remaining = getElementHealth(source) - (loss or 0)
    if remaining > 0 then
        return
    end

    setElementHealth(source, BLACKOUT_HP)
    BlackoutService.start(source)
end)

--- Fallback for fatal damage that never reaches onPlayerDamage at all -
--- MTA's own docs confirm onPlayerDamage simply does not fire for damage
--- that kills the player (fall damage, drowning, explosions, or any other
--- cause included), onPlayerWasted fires instead. The player is already
--- dead/ragdolled by the time this fires, so this has to revive them in
--- place rather than just correct their health.
addEventHandler("onPlayerWasted", root, function()
    if getElementData(source, ElementData.Player.SPAWNED) ~= true then
        return
    end

    reviveInPlace(source)
    BlackoutService.start(source)
end)

--- Per-player countdown sweep - ends blackout once the timer naturally
--- runs out. A single shared timer for everyone currently blacked out,
--- not one setTimer per player, since this only needs to run once a
--- second regardless of how many players are down.
setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do
        if BlackoutService.isBlackedOut(player) and BlackoutService.secondsRemaining(player) <= 0 then
            BlackoutService.finish(player)
        end
    end
end, 1000, 0)

--- Client -> server: E pressed while blacked out, requesting to end
--- blackout early instead of waiting for a future medic system. Server
--- re-derives "is the countdown actually over" itself - never trusts that
--- the client only sent this once its own local timer allowed it.
addEvent(Events.BLACKOUT_SELF_REVIVE, true)
addEventHandler(Events.BLACKOUT_SELF_REVIVE, root, function()
    local player = client
    local remaining = BlackoutService.secondsRemaining(player)
    if remaining == nil or remaining > 0 then
        return
    end

    BlackoutService.finish(player)
end)

--- A player already connected when this resource (re)starts mid-session
--- needs their blackout state re-broadcast to their own (freshly
--- restarted) client - ElementData.Player.BLACKOUT_UNTIL survives a
--- gm_blackout restart (it lives on the player element, not in this
--- resource's own Lua state), but the client-side overlay does not.
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if BlackoutService.isBlackedOut(player) then
            local duration = getElementData(player, ElementData.Player.BLACKOUT_DURATION)
            triggerClientEvent(player, Events.BLACKOUT_STARTED, player, BlackoutService.secondsRemaining(player), type(duration) == "number" and duration or BLACKOUT_DURATION_S)
        end
    end
end)

function blackoutServiceIsBlackedOut(player) return BlackoutService.isBlackedOut(player) end
function blackoutServiceStart(player, durationSeconds) BlackoutService.start(player, durationSeconds) end
function blackoutServiceFinish(player) BlackoutService.finish(player) end
