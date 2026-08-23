-- Thin facade over the Vehicle Active Record model - VehicleService (in
-- gm_vehicles) calls this, never Vehicle/Model/QueryBuilder directly.
-- Also owns the toJSON/fromJSON boundary for this model's "text" columns
-- (position/rotation/upgrades/doors/lights/panels/wheels/color/
-- last_drivers) - every row this repository hands back has those fields
-- already decoded into real Lua tables, and every write here JSON-encodes
-- them before they reach the database. Callers above this file never see
-- a JSON string.
VehicleRepository = VehicleRepository or {}

local JSON_COLUMNS = { "position", "rotation", "upgrades", "doors", "lights", "panels", "wheels", "color", "last_drivers" }

-- gm_vehicles (a separate resource) has no access to Model.NULL - see
-- ItemRepository.lua's own NULL_SENTINEL comment for the full reasoning
-- (triggerEvent copies tables across the resource boundary rather than
-- preserving identity, so Model.NULL's reference-equality sentinel trick
-- can't survive the trip). gm_vehicles sends this string constant instead
-- (see VehicleStorageService.lua's retrieve handler, clearing store_id)
-- and this file translates it to the real Model.NULL right before it
-- reaches QueryBuilder.
local NULL_SENTINEL = "__VEHICLE_REPOSITORY_NULL__"

--- @param vehicle table a Vehicle instance (or plain row) - mutated in place
-- @return table the same table, for chaining
local function decodeJsonColumns(vehicle)
    if not vehicle then
        return vehicle
    end
    for _, column in ipairs(JSON_COLUMNS) do
        if type(vehicle[column]) == "string" then
            vehicle[column] = fromJSON(vehicle[column]) or nil
        end
    end
    return vehicle
end

--- @param attributes table plain column -> value, JSON columns as real
--        Lua tables, NULL_SENTINEL for an explicit SQL NULL
-- @return table a NEW table (does not mutate `attributes`) with JSON
--         columns encoded and NULL_SENTINEL translated to Model.NULL
local function encodeJsonColumns(attributes)
    local encoded = {}
    for key, value in pairs(attributes) do
        if value == NULL_SENTINEL then
            encoded[key] = Model.NULL
        else
            encoded[key] = value
        end
    end
    for _, column in ipairs(JSON_COLUMNS) do
        if type(encoded[column]) == "table" and encoded[column] ~= Model.NULL then
            encoded[column] = toJSON(encoded[column])
        end
    end
    return encoded
end

--- @param id number
-- @param callback function(ok: boolean, vehicleOrError: table|nil|string)
VehicleRepository.findById = function(id, callback)
    Vehicle:find(id, function(ok, vehicle)
        callback(ok, ok and decodeJsonColumns(vehicle) or vehicle)
    end)
end

--- @param accountId number
-- @param callback function(ok: boolean, vehiclesOrError: table|string)
VehicleRepository.findByOwnerAccountId = function(accountId, callback)
    Vehicle:where("owner_account_id", accountId):orderBy("created_at", "ASC"):get(function(ok, vehicles)
        if not ok then
            callback(false, vehicles)
            return
        end
        for _, vehicle in ipairs(vehicles) do
            decodeJsonColumns(vehicle)
        end
        callback(true, vehicles)
    end)
end

--- Every PRIVATE vehicle NOT sitting in storage (store_id IS NULL), for
--- restoring the world at resource start - see gm_vehicles/server/
--- VehicleService.lua's onResourceStart handler. A stored vehicle is
--- deliberately excluded here - it stays absent from the world until
--- retrieved (see VehicleStorageService.lua).
-- @param callback function(ok: boolean, vehiclesOrError: table|string)
VehicleRepository.findAllPrivate = function(callback)
    Vehicle:where("purpose", Enums.VehiclePurpose.PRIVATE):where("store_id", Model.NULL):get(function(ok, vehicles)
        if not ok then
            callback(false, vehicles)
            return
        end
        for _, vehicle in ipairs(vehicles) do
            decodeJsonColumns(vehicle)
        end
        callback(true, vehicles)
    end)
end

--- Every vehicle this account owns that's currently sitting in the given
--- storage lot (store_id = storeId) - the list gm_vehicles/client's own
--- storage panel shows when a player walks up to that lot's marker.
-- @param accountId number
-- @param storeId number
-- @param callback function(ok: boolean, vehiclesOrError: table|string)
VehicleRepository.findByOwnerAndStoreId = function(accountId, storeId, callback)
    Vehicle:where("owner_account_id", accountId):where("store_id", storeId):orderBy("created_at", "ASC"):get(function(ok, vehicles)
        if not ok then
            callback(false, vehicles)
            return
        end
        for _, vehicle in ipairs(vehicles) do
            decodeJsonColumns(vehicle)
        end
        callback(true, vehicles)
    end)
end

--- Every vehicle (any owner) currently sitting in the given storage lot -
--- used only to check whether a lot is empty before deleting it, see
--- core/server/commands/AdminCommands.lua's "/removestore".
-- @param storeId number
-- @param callback function(ok: boolean, vehiclesOrError: table|string)
VehicleRepository.findByStoreId = function(storeId, callback)
    Vehicle:where("store_id", storeId):get(function(ok, vehicles)
        if not ok then
            callback(false, vehicles)
            return
        end
        for _, vehicle in ipairs(vehicles) do
            decodeJsonColumns(vehicle)
        end
        callback(true, vehicles)
    end)
end

--- Every GROUP-purpose vehicle NOT sitting in storage (store_id IS NULL) -
--- the group-owned analogue of findAllPrivate, for restoring the world at
--- resource start.
-- @param callback function(ok: boolean, vehiclesOrError: table|string)
VehicleRepository.findAllGroupOwned = function(callback)
    Vehicle:where("purpose", Enums.VehiclePurpose.GROUP):where("store_id", Model.NULL):get(function(ok, vehicles)
        if not ok then
            callback(false, vehicles)
            return
        end
        for _, vehicle in ipairs(vehicles) do
            decodeJsonColumns(vehicle)
        end
        callback(true, vehicles)
    end)
end

--- Every vehicle belonging to a group, any store_id (both spawned in the
--- world and sitting in a lot) - used by gm_groups' own CEF Vehicles tab
--- listing and by VehicleStorageService.lua's group-lot filtering.
-- @param groupId number
-- @param callback function(ok: boolean, vehiclesOrError: table|string)
VehicleRepository.findByGroupId = function(groupId, callback)
    Vehicle:where("group_id", groupId):orderBy("created_at", "ASC"):get(function(ok, vehicles)
        if not ok then
            callback(false, vehicles)
            return
        end
        for _, vehicle in ipairs(vehicles) do
            decodeJsonColumns(vehicle)
        end
        callback(true, vehicles)
    end)
end

--- @param attributes table column -> value (JSON columns as real Lua tables, not encoded)
-- @param callback function(ok: boolean, vehicleOrError: table|string)
VehicleRepository.create = function(attributes, callback)
    Vehicle:create(encodeJsonColumns(attributes), function(ok, vehicle)
        callback(ok, ok and decodeJsonColumns(vehicle) or vehicle)
    end)
end

--- @param id number
-- @param attributes table column -> value (JSON columns as real Lua tables, not encoded)
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
VehicleRepository.update = function(id, attributes, callback)
    Vehicle:query():where("id", id):update(encodeJsonColumns(attributes), callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
VehicleRepository.delete = function(id, callback)
    Vehicle:query():where("id", id):delete(callback)
end

-- Deliberately NO flat exported wrappers here - every method above takes
-- a callback, and this project's hard rule (see docs/Architecture.md's
-- "The one hard rule for extending the project") is that a callback must
-- never cross a resource boundary: MTA exports can't safely carry a
-- function value to another resource's isolated Lua environment. gm_vehicles
-- (a separate resource) reaches this repository through
-- VehicleService.lua's event-based request/response bridge instead - the
-- exact same pattern FetchBridge uses across the core/core_ui boundary
-- (see Architecture.md's "FetchBridge across the core/core_ui boundary").
