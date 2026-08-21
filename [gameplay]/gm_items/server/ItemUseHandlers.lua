-- Per-Enums.ItemType "use" effect, keyed by scheme.type - ItemService.use
-- looks up the item's scheme type here and runs the matching handler.
-- Enums.ItemType.PLAIN has no entry (using a plain stackable item, e.g.
-- a fish, is a no-op - nothing happens beyond opening the panel's context
-- menu, matching the reference implementation's own `type == 0 then
-- return true` no-op branch).
ITEM_USE_HANDLERS = {}

-- Vehicle key: toggles the target vehicle's lock via gm_vehicles' own
-- toggleVehicleLock export (plain data in/out - safe across the resource
-- boundary per docs/Architecture.md's "the one hard rule") instead of
-- calling setVehicleLocked directly, so the headlight-flash signal
-- (gm_vehicles/server/VehicleLockService.lua) fires here too, not just
-- from gm_vehicles' own callers. item.itemValues = { vehicleId } -
-- vehicleId is a gm_vehicles database row id (see VehicleService.lua's
-- spawnFromRow / ElementData.Vehicle.ID), resolved to the live world
-- vehicle element by scanning getElementsByType (gm_vehicles doesn't
-- export an id->element lookup today).
ITEM_USE_HANDLERS[Enums.ItemType.VEHICLE_KEY] = function(player, item, scheme)
    local vehicleId = item.itemValues[1]
    if not vehicleId then
        return
    end

    local target = nil
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        if getElementData(vehicle, ElementData.Vehicle.ID) == vehicleId then
            target = vehicle
            break
        end
    end

    if not target then
        return
    end

    local px, py, pz = getElementPosition(player)
    local vx, vy, vz = getElementPosition(target)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > 40 then
        return
    end

    exports.gm_vehicles:toggleVehicleLock(target)
end
