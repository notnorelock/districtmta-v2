-- Thin facade over the GroupVehicleRank Active Record model - mirrors
-- GroupMemberRepository.lua's own shape/conventions. No JSON columns.
GroupVehicleRankRepository = GroupVehicleRankRepository or {}

--- @param vehicleId number
-- @param callback function(ok: boolean, rowsOrError: table|string)
GroupVehicleRankRepository.findByVehicleId = function(vehicleId, callback)
    GroupVehicleRank:where("vehicle_id", vehicleId):get(callback)
end

--- Replaces the ENTIRE allowlist for `vehicleId` with `rankIds` - deletes
--- every existing row for this vehicle, then inserts one row per new rank
--- id. Simplest correct approach for a small (a handful of ranks) per-
--- vehicle allowlist; this ORM has no transaction primitive (see
--- QueryBuilder.lua), so a crash mid-sequence could in principle leave the
--- allowlist empty rather than partially-old/partially-new - acceptable
--- for v1 given this is an admin/leader-only, infrequent edit, not a
--- money-adjacent or high-frequency write.
-- @param vehicleId number
-- @param rankIds number[]
-- @param callback function(ok: boolean, error: string|nil)
GroupVehicleRankRepository.setForVehicle = function(vehicleId, rankIds, callback)
    GroupVehicleRank:query():where("vehicle_id", vehicleId):delete(function(deleteOk, deleteErr)
        if not deleteOk then
            callback(false, deleteErr)
            return
        end

        local pending = #rankIds
        if pending == 0 then
            callback(true)
            return
        end

        local failed = nil
        for _, rankId in ipairs(rankIds) do
            GroupVehicleRank:create({ vehicle_id = vehicleId, rank_id = rankId }, function(createOk, createErr)
                if not createOk then
                    failed = createErr
                end
                pending = pending - 1
                if pending <= 0 then
                    callback(failed == nil, failed)
                end
            end)
        end
    end)
end

--- Cascade helper for vehicle deletion - deletes every allowlist row for
--- `vehicleId` (this ORM has no ON DELETE CASCADE).
-- @param vehicleId number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupVehicleRankRepository.deleteByVehicleId = function(vehicleId, callback)
    GroupVehicleRank:query():where("vehicle_id", vehicleId):delete(callback)
end

-- Deliberately no flat exported wrappers - see VehicleRepository.lua's own
-- module comment on why. gm_groups reaches this through
-- core/server/GroupService.lua's bridge, never directly.
