-- Thin facade over the VehicleStore Active Record model - mirrors
-- VehicleRepository.lua's own shape/conventions exactly. Owns the
-- toJSON/fromJSON boundary for enter_position/spawn_positions - every row
-- this repository hands back has those fields already decoded into real
-- Lua tables.
VehicleStoreRepository = VehicleStoreRepository or {}

local JSON_COLUMNS = { "enter_position", "store_position", "spawn_positions" }

--- @param store table a VehicleStore instance (or plain row) - mutated in place
-- @return table the same table, for chaining
local function decodeJsonColumns(store)
    if not store then
        return store
    end
    for _, column in ipairs(JSON_COLUMNS) do
        if type(store[column]) == "string" then
            store[column] = fromJSON(store[column]) or nil
        end
    end
    return store
end

--- @param callback function(ok: boolean, storesOrError: table|string)
VehicleStoreRepository.findAll = function(callback)
    VehicleStore:query():get(function(ok, stores)
        if not ok then
            callback(false, stores)
            return
        end
        for _, store in ipairs(stores) do
            decodeJsonColumns(store)
        end
        callback(true, stores)
    end)
end

--- @param id number
-- @param callback function(ok: boolean, storeOrError: table|nil|string)
VehicleStoreRepository.findById = function(id, callback)
    VehicleStore:find(id, function(ok, store)
        callback(ok, ok and decodeJsonColumns(store) or store)
    end)
end

--- @param attributes table column -> value (JSON columns as real Lua tables, not encoded)
-- @param callback function(ok: boolean, storeOrError: table|string)
VehicleStoreRepository.create = function(attributes, callback)
    local encoded = {}
    for key, value in pairs(attributes) do
        encoded[key] = value
    end
    for _, column in ipairs(JSON_COLUMNS) do
        if type(encoded[column]) == "table" then
            encoded[column] = toJSON(encoded[column])
        end
    end

    VehicleStore:create(encoded, function(ok, store)
        callback(ok, ok and decodeJsonColumns(store) or store)
    end)
end

--- @param id number
-- @param attributes table column -> value (JSON columns as real Lua tables, not encoded)
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
VehicleStoreRepository.update = function(id, attributes, callback)
    local encoded = {}
    for key, value in pairs(attributes) do
        encoded[key] = value
    end
    for _, column in ipairs(JSON_COLUMNS) do
        if type(encoded[column]) == "table" then
            encoded[column] = toJSON(encoded[column])
        end
    end

    VehicleStore:query():where("id", id):update(encoded, callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
VehicleStoreRepository.delete = function(id, callback)
    VehicleStore:query():where("id", id):delete(callback)
end

-- Deliberately NO flat exported wrappers - see VehicleRepository.lua's own
-- module comment on why (a callback can never cross a resource boundary).
-- gm_vehicles reaches this through VehicleService.lua's (core) existing
-- VEHICLE_REPOSITORY_REQUEST/_RESPONSE bridge, not a new channel. This
-- file's own create/update/delete are only ever called directly from
-- WITHIN core itself (core/server/commands/AdminCommands.lua's
-- /createstore, /addstorespawn, /removestore - same-resource, no bridge
-- needed), never from gm_vehicles.
