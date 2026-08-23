-- Group-vehicle access decision + the CEF panel's "Pojazdy" tab
-- (list group vehicles, edit a vehicle's allowed-rank list). The actual
-- access GATE lives in OTHER resources (gm_vehicles_interaction's own
-- canStartEngine, gm_interactions' own hasVehicleKey) - they call the
-- flat groupServiceCanUseVehicle export below (plain data in/out,
-- synchronous - a cross-resource MTA export can't await a DB round trip,
-- see MembershipCache.lua's own module comment on why membership/rank
-- identity is cached in-memory specifically to make this possible).
GroupVehicleService = GroupVehicleService or {}

--- @param name string exact group name (case-sensitive - group names are
--        unique, see Group.lua's own `unique = true`)
-- @return number|false the group's id, or false if no group has this name -
--         gm_vehicles' own /creategroupvehicle command uses this to
--         resolve its <groupName> argument (a plain data in/out export,
--         same synchronous shape as groupServiceCanUseVehicle - GroupCache
--         is already fully in-memory so no DB round trip is needed here either).
function groupServiceFindGroupIdByName(name)
    for _, group in pairs(GroupCache.all()) do
        if group.name == name then
            return group.id
        end
    end
    return false
end

--- @param groupId number
-- @return string|false the group's name, or false if unknown - used by
--         gm_vehicles_interaction's own onVehicleStartEnter block to name
--         the group in its "this vehicle belongs to X" rejection message.
function groupServiceGetGroupName(groupId)
    local group = GroupCache.get(groupId)
    return group and group.name or false
end

--- Refreshes GroupCache's own vehicles/vehicleRankAllowlist for one group
--- from the database - gm_vehicles' own /creategroupvehicle calls this
--- right after creating a new group vehicle so groupServiceCanUseVehicle
--- and the CEF Vehicles tab see it without a full GroupCache.reload().
--- Fire-and-forget (no callback - a cross-resource export can't hand one
--- back either way, see docs/Architecture.md's "the one hard rule").
-- @param groupId number
function groupServiceReloadVehicles(groupId)
    GroupCache.reloadVehiclesForGroup(groupId)
end

--- @param player element
-- @param vehicleId number a vehicles table id (ElementData.Vehicle.ID)
-- @param groupId number the vehicle's own ElementData.Vehicle.GROUP_ID
-- @return boolean
function groupServiceCanUseVehicle(player, vehicleId, groupId)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return false
    end

    local isMember, rankId = MembershipCache.get(accountId, groupId)
    if not isMember or not rankId then
        return false
    end

    local group = GroupCache.get(groupId)
    if not group then
        return false
    end

    if group.type == "fraction" then
        local status = GroupDutyService.getMemberDutyStatus(player)
        if not status or status.groupId ~= groupId then
            return false
        end
    end

    local vehicleInfo = GroupCache.getVehicle(vehicleId)
    if not vehicleInfo then
        return false
    end

    -- The fraction's own leader always has access to every one of the
    -- group's vehicles, bypassing the per-vehicle rank allowlist entirely
    -- (they still had to pass the on-duty check above like anyone else -
    -- this only skips the allowlist, not duty) - confirmed with the user:
    -- fraction leaders shouldn't need to remember to add their own rank
    -- to every vehicle they create. Gang/organization leaders get no such
    -- bypass - only fraction, matching the duty-gate's own type == "fraction" scope.
    if group.type == "fraction" and group.leaderAccountId == accountId then
        return true
    end

    return vehicleInfo.allowlist[rankId] == true
end

--- Coarser than groupServiceCanUseVehicle - reports WHY a player has no
--- access to a group's vehicles in general (not tied to any one specific
--- vehicle's rank allowlist), for gm_vehicles' own VehicleStorageService.lua
--- to notify a player walking into an empty-for-them GROUP-purpose lot
--- with a specific reason instead of a silent empty panel.
-- @param player element
-- @param groupId number
-- @return string one of "ok" | "not_member" | "no_rank" | "not_on_duty"
function groupServiceGetMembershipStatus(player, groupId)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return "not_member"
    end

    local isMember, rankId = MembershipCache.get(accountId, groupId)
    if not isMember then
        return "not_member"
    end
    if not rankId then
        return "no_rank"
    end

    local group = GroupCache.get(groupId)
    if group and group.type == "fraction" and group.leaderAccountId ~= accountId then
        local status = GroupDutyService.getMemberDutyStatus(player)
        if not status or status.groupId ~= groupId then
            return "not_on_duty"
        end
    end

    return "ok"
end

--- @param group table cached group entry (GroupCache shape)
-- @return table[] plain-data vehicle entries for the CEF panel
local function toVehicleEntries(group)
    local entries = {}
    for vehicleId, vehicleRow in pairs(group.vehicles) do
        local allowlist = group.vehicleRankAllowlist[vehicleId] or {}
        local allowedRankIds = {}
        for rankId in pairs(allowlist) do
            allowedRankIds[#allowedRankIds + 1] = rankId
        end

        entries[#entries + 1] = {
            id = vehicleRow.id,
            model = vehicleRow.model,
            allowedRankIds = allowedRankIds,
        }
    end
    return entries
end

--- Every group member (not just manage_ranks) can see the vehicle list -
--- only editing the allowlist is gated, see GROUP_SET_VEHICLE_RANKS below.
-- @param player element
-- @param groupId number
local function sendVehicles(player, groupId)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    local isMember = MembershipCache.get(accountId, groupId)
    if not isMember then
        return
    end

    local group = GroupCache.get(groupId)
    if not group then
        return
    end

    triggerClientEvent(player, Events.GROUP_VEHICLES_RECEIVED, resourceRoot, { groupId = groupId, vehicles = toVehicleEntries(group) })
end

addEvent(Events.GROUP_REQUEST_VEHICLES, true)
addEventHandler(Events.GROUP_REQUEST_VEHICLES, root, function(data)
    if type(data) ~= "table" or type(data.groupId) ~= "number" then
        return
    end
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end
    sendVehicles(client, data.groupId)
end)

addEvent(Events.GROUP_SET_VEHICLE_RANKS, true)
addEventHandler(Events.GROUP_SET_VEHICLE_RANKS, root, function(data)
    if type(data) ~= "table" or type(data.vehicleId) ~= "number" or type(data.rankIds) ~= "table" then
        return
    end
    local player = client

    local vehicleInfo = GroupCache.getVehicle(data.vehicleId)
    if not vehicleInfo then
        return
    end
    local groupId = vehicleInfo.group.id

    -- requirePermission is a local function inside GroupEndpoints.lua -
    -- GroupVehicleService.lua loads AFTER it (see meta.xml), but Lua
    -- `local` scoping is per-FILE, not per-resource, so it isn't visible
    -- here. Re-derive the same manage_ranks-or-leader check directly
    -- against MembershipCache/GroupCache instead of duplicating
    -- GroupEndpoints.lua's own DB-round-trip requirePermission - this
    -- runs off the same in-memory data groupServiceCanUseVehicle already
    -- trusts, so there's no correctness gap, just a different (cache-
    -- backed) source for the permission check.
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end
    local isMember, rankId = MembershipCache.get(accountId, groupId)
    if not isMember or not rankId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do wykonania tej akcji." })
        return
    end
    local rank = GroupCache.getRank(rankId)
    local permissions = rank and rank.permissions
    local allowed = type(permissions) == "table" and (permissions.is_leader == true or permissions.manage_ranks == true)
    if not allowed then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do wykonania tej akcji." })
        return
    end

    local rankIds = {}
    for _, value in ipairs(data.rankIds) do
        if type(value) == "number" then
            rankIds[#rankIds + 1] = value
        end
    end

    GroupVehicleBridge.call("setVehicleRanks", { data.vehicleId, rankIds }, function(ok, err)
        if not ok then
            Logger.error("GroupVehicleService", "Failed to set vehicle ranks", { vehicleId = data.vehicleId, error = tostring(err) })
            if isElement(player) then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się zapisać uprawnień pojazdu." })
            end
            return
        end

        -- Update the in-memory allowlist directly rather than a full
        -- GroupCache.reload - cheap, avoids re-fetching every group's
        -- ranks/vehicles for a single-vehicle edit.
        local allowlist = {}
        for _, id in ipairs(rankIds) do
            allowlist[id] = true
        end
        vehicleInfo.group.vehicleRankAllowlist[data.vehicleId] = allowlist

        if isElement(player) then
            NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Zaktualizowano uprawnienia pojazdu." })
            sendVehicles(player, groupId)
        end
    end)
end)
