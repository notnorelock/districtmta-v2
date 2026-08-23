-- Group duty: walking into a group's duty marker TOGGLES duty for it -
-- swaps to the member's current rank's skin, tracks accrued on-duty
-- seconds server-side via a periodic tick (never client-reported), and
-- restores the pre-duty skin when toggled off. Simply walking back out of
-- the marker does NOT end the session by itself (see enterDuty/
-- onLeaveZone's own comments) - only re-entering the same marker,
-- disconnecting, or an admin/leader moving the duty point (reload) ends
-- it, so a member can step away from their post without losing accrued
-- time. Marker/colshape locations are
-- admin-configured (Group.duty_position, set via GroupCommands.lua's
-- /setgroupduty), loaded once at resource start and again any time
-- GroupCommands.lua/GroupEndpoints.lua call GroupDutyService.reload()
-- directly (same-resource, no event needed) - same shape as gm_vehicles/
-- server/VehicleStorageService.lua's own enter-marker reload, just
-- triggered by a direct function call here instead of a broadcast event
-- since nothing outside this resource needs to know a group's duty point moved.
GroupDutyService = GroupDutyService or {}

-- How often accrued duty seconds are flushed to the database and synced
-- to the client's own HUD - short enough that a crash/restart never loses
-- more than this much unpaid time, long enough to not hammer the bridge.
local DUTY_TICK_INTERVAL_MS = 10000

local MARKER_COLOR_BY_TYPE = {
    gang = { 231, 76, 60 },        -- red
    organization = { 52, 152, 219 }, -- blue
    fraction = { 242, 184, 74 },     -- gold
}

-- marker/colshape element -> group entry (GroupCache shape) - both
-- elements created for a group's duty point map to the same entry, only
-- ever iterated for reload()/onResourceStop's own destroyElement cleanup.
local dutyZones = {}

-- player -> { groupId, memberId, rankId, startedAt = getTickCount(), lastTickAt = getTickCount() }
local dutySessions = {}
-- player -> skin model id they had before entering duty, restored on exit
local preDutySkins = {}
-- player -> group entry they're currently standing inside the duty marker of
local playersInZone = {}

--- @param player element
-- @param groupId number
-- @param callback function(memberRow: table|nil) - nil if not a member,
--        or a member with no rank assigned yet (can't enter duty either way)
local function findMembership(player, groupId, callback)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        callback(nil)
        return
    end

    GroupBridge.call("findMembersByAccountId", { accountId }, function(ok, membersOrError)
        if not ok then
            Logger.error("GroupDutyService", "Failed to load memberships", { error = tostring(membersOrError) })
            callback(nil)
            return
        end

        for _, member in ipairs(membersOrError) do
            if member.group_id == groupId then
                callback(member)
                return
            end
        end
        callback(nil)
    end)
end

--- Flushes elapsed-since-last-tick seconds for `player`'s active session
--- (if any) and returns the flushed amount - shared by both the periodic
--- tick and exitDuty's own final flush, so exiting mid-interval never
--- silently drops the last few seconds.
-- @param player element
-- @return number seconds flushed (0 if no active session)
local function flushElapsed(player)
    local session = dutySessions[player]
    if not session then
        return 0
    end

    local now = getTickCount()
    local elapsedMs = now - session.lastTickAt
    session.lastTickAt = now

    local seconds = math.floor(elapsedMs / 1000)
    if seconds <= 0 then
        return 0
    end

    GroupBridge.call("incrementMemberDutySeconds", { session.memberId, seconds }, function(ok, affectedOrError)
        if not ok then
            Logger.error("GroupDutyService", "Failed to flush duty seconds", { memberId = session.memberId, error = tostring(affectedOrError) })
        end
    end)

    return seconds
end

--- Walking into a group's duty marker TOGGLES duty for that group - in
--- (not already on duty for it) starts a session, in again (already on
--- duty for it) ends it. Walking back OUT of the marker does nothing on
--- its own (see onLeaveZone) - a player can step away from their duty
--- point without losing their session, only re-entering the same marker
--- (or /dutypayout's own implicit nothing, or disconnecting) ends it.
-- @param player element
-- @param group table cached group entry (GroupCache shape)
local function enterDuty(player, group)
    if dutySessions[player] and dutySessions[player].groupId == group.id then
        GroupDutyService.exitDuty(player, "toggled_off")
        return
    end

    findMembership(player, group.id, function(member)
        if not isElement(player) or playersInZone[player] ~= group then
            -- Left the zone (or disconnected) before the membership query came back.
            return
        end

        if not member then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie należysz do tej grupy." })
            return
        end

        if not member.rank_id then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Lider nie ustawił tobie rangi w tej grupie." })
            return
        end

        local rank = GroupCache.getRank(member.rank_id)
        if not rank then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Twoja ranga nie istnieje już w tej grupie." })
            return
        end

        -- If already on duty for a DIFFERENT group, leave that one first
        -- (one active duty session at a time, even though membership
        -- itself can span multiple groups).
        if dutySessions[player] then
            GroupDutyService.exitDuty(player, "switched_group")
        end

        preDutySkins[player] = getElementModel(player)
        setElementModel(player, rank.skin)

        dutySessions[player] = {
            groupId = group.id,
            memberId = member.id,
            rankId = rank.id,
            startedAt = getTickCount(),
            lastTickAt = getTickCount(),
        }

        -- Presence-check convention, same as ElementData.Player.ADMIN -
        -- read as `type(getElementData(...)) == "table"`, never `~= nil`.
        -- gm_scoreboard/gm_nametags read this directly (no cross-resource
        -- call into gm_groups needed) to compose their own status text.
        -- Copies just the fields needed into fresh { group = {...}, rank
        -- = {...} } tables rather than storing `group`/`rank` themselves
        -- by reference - those are GroupCache's own internal tables,
        -- wholesale-replaced on every GroupCache.reload(), which would
        -- leave this ElementData pointing at a stale/orphaned table.
        setElementData(player, ElementData.Player.GROUP_DUTY, {
            group = { id = group.id, name = group.name, type = group.type },
            rank = { id = rank.id, name = rank.name },
        })

        NotificationService.send(player, {
            type = Enums.NotificationType.INFO,
            message = (group.type == "gang" and "Podejmujesz działalność przestępczą: " or "Podejmujesz służbę: ") .. group.name,
        })

        triggerClientEvent(player, Events.GROUP_DUTY_STARTED, resourceRoot, {
            groupName = group.name,
            groupType = group.type,
            rankName = rank.name,
            totalSeconds = member.stat_workduty_seconds or 0,
        })
    end)
end

--- @param player element
-- @param reason string "toggled_off" | "disconnect" | "kicked_from_group" | "switched_group" | "duty_position_reloaded" | "left_group" | "group_deleted" | "resource_stop"
GroupDutyService.exitDuty = function(player, reason)
    local session = dutySessions[player]
    if not session then
        return
    end

    flushElapsed(player)
    dutySessions[player] = nil

    if isElement(player) then
        removeElementData(player, ElementData.Player.GROUP_DUTY)

        local preDutySkin = preDutySkins[player]
        if preDutySkin then
            setElementModel(player, preDutySkin)
        end

        local group = GroupCache.get(session.groupId)
        NotificationService.send(player, {
            type = Enums.NotificationType.INFO,
            message = (group and group.type == "gang" and "Działalność przestępcza" or "Służba") .. " zakończona.",
        })

        triggerClientEvent(player, Events.GROUP_DUTY_ENDED, resourceRoot)
    end
    preDutySkins[player] = nil
end

--- @param player element
-- @return table|nil { groupId, memberId, rankId, startedAt } if currently on duty
GroupDutyService.getMemberDutyStatus = function(player)
    return dutySessions[player]
end

local function onEnterZone(group, player)
    playersInZone[player] = group
    enterDuty(player, group)
end

--- Only clears the zone-membership tracking used by enterDuty's own
--- race guard (see its findMembership callback) - does NOT end an active
--- duty session. Duty is a toggle now: walking into the marker again (or
--- disconnecting) is what actually ends it, see enterDuty/onPlayerQuit.
-- @param player element
local function onLeaveZone(player)
    playersInZone[player] = nil
end

addEventHandler("onPlayerQuit", root, function()
    GroupDutyService.exitDuty(source, "disconnect")
end)

local dutyTickTimer = nil

local function runDutyTick()
    for player, session in pairs(dutySessions) do
        if not isElement(player) then
            dutySessions[player] = nil
        else
            local flushedSeconds = flushElapsed(player)
            if flushedSeconds > 0 then
                -- totalSeconds is an estimate (last known DB total +
                -- this flush) - the client's own local ticker smooths
                -- between syncs and self-corrects on the next push, so a
                -- slightly-stale base here is not a correctness issue.
                triggerClientEvent(player, Events.GROUP_DUTY_SYNC, resourceRoot, { totalSeconds = flushedSeconds })
            end
        end
    end
end

--- Destroys every currently-spawned duty marker/zone and re-fetches
--- groups+ranks from scratch, rebuilding both the cache (GroupCache.reload)
--- and the markers for the new set - called once at startup and again any
--- time GroupEndpoints.lua/GroupCommands.lua mutate a group's duty
--- position, so an admin/leader editing it never has to manually restart
--- this whole resource. Also kicks any player currently standing inside a
--- zone back out of duty first (its marker element is about to be
--- destroyed and recreated, so it can never fire its own onMarkerLeave
--- for them).
-- @param callback function()|nil called once the reload finishes
GroupDutyService.reload = function(callback)
    for player in pairs(playersInZone) do
        onLeaveZone(player)
        GroupDutyService.exitDuty(player, "duty_position_reloaded")
    end

    for zone in pairs(dutyZones) do
        if isElement(zone) then
            destroyElement(zone)
        end
    end
    dutyZones = {}

    GroupCache.reload(function()
        for _, group in pairs(GroupCache.all()) do
            local position = group.dutyPosition
            if type(position) == "table" and position.x and position.y and position.z then
                local color = MARKER_COLOR_BY_TYPE[group.type] or MARKER_COLOR_BY_TYPE.organization
                if group.color and #group.color == 7 then
                    local r = tonumber(group.color:sub(2, 3), 16)
                    local g = tonumber(group.color:sub(4, 5), 16)
                    local b = tonumber(group.color:sub(6, 7), 16)
                    if r and g and b then
                        color = { r, g, b }
                    end
                end

                local marker = createMarker(position.x, position.y, position.z - 0.9, "cylinder", 2, color[1], color[2], color[3], 100)
                setElementInterior(marker, position.interior or 0)
                setElementDimension(marker, position.dimension or 0)
                setElementData(marker, "text", group.type == "fraction" and string.format("Służba %s", group.name) or "Duty")
                dutyZones[marker] = group

                local col = createColSphere(position.x, position.y, position.z, 1.5)
                setElementInterior(col, position.interior or 0)
                setElementDimension(col, position.dimension or 0)
                dutyZones[col] = group

                addEventHandler("onColShapeHit", col, function(hitElement, matchingDimension)
                    if getElementType(hitElement) ~= "player" or not matchingDimension or isPedInVehicle(hitElement) then
                        return
                    end
                    onEnterZone(group, hitElement)
                end)

                addEventHandler("onColShapeLeave", col, function(hitElement, matchingDimension)
                    if getElementType(hitElement) ~= "player" or not matchingDimension then
                        return
                    end
                    onLeaveZone(hitElement)
                end)
            end
        end

        if isTimer(dutyTickTimer) then
            killTimer(dutyTickTimer)
        end
        dutyTickTimer = setTimer(runDutyTick, DUTY_TICK_INTERVAL_MS, 0)

        -- Rebuilds AFTER GroupCache so it can read the fresh group id
        -- list off GroupCache.all() - see MembershipCache.lua's own
        -- module comment on why this stays a separate cache from
        -- GroupCache's own deliberate "never cache members" stance.
        MembershipCache.reload(function()
            if callback then callback() end
        end)
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Same DATABASE_READY/schemaIsMigrated gotcha VehicleStorageService.lua
    -- documents - a fresh table sorted late can still be mid-CREATE TABLE
    -- when this resource's own onResourceStart fires.
    local migratedOk, migrated = pcall(function() return exports.core:schemaIsMigrated() end)
    if migratedOk and migrated then
        GroupDutyService.reload()
    else
        addEvent(Events.DATABASE_READY, true)
        addEventHandler(Events.DATABASE_READY, root, function() GroupDutyService.reload() end)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(dutySessions) do
        GroupDutyService.exitDuty(player, "resource_stop")
    end

    for zone in pairs(dutyZones) do
        if isElement(zone) then
            destroyElement(zone)
        end
    end
    dutyZones = {}

    if isTimer(dutyTickTimer) then
        killTimer(dutyTickTimer)
    end
end)
