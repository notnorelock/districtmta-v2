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

--- @param attributes table plain column -> value, JSON columns as real Lua tables
-- @return table a NEW table (does not mutate `attributes`) with JSON columns encoded
local function encodeJsonColumns(attributes)
    local encoded = {}
    for key, value in pairs(attributes) do
        encoded[key] = value
    end
    for _, column in ipairs(JSON_COLUMNS) do
        if type(encoded[column]) == "table" then
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

--- Every PRIVATE vehicle, for restoring the world at resource start -
--- see gm_vehicles/server/VehicleService.lua's onResourceStart handler.
-- @param callback function(ok: boolean, vehiclesOrError: table|string)
VehicleRepository.findAllPrivate = function(callback)
    Vehicle:where("purpose", Enums.VehiclePurpose.PRIVATE):get(function(ok, vehicles)
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
