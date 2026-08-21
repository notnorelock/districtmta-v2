-- Thin facade over the Item Active Record model - gm_items' ItemService
-- calls this, never Item/Model/QueryBuilder directly. Also owns the
-- toJSON/fromJSON boundary for this model's "text" columns (item_values/
-- flags/position) - every row this repository hands back has those
-- fields already decoded into real Lua tables (position may be nil, for
-- a carried item), and every write here JSON-encodes them before they
-- reach the database. Callers above this file never see a JSON string.
ItemRepository = ItemRepository or {}

local JSON_COLUMNS = { "item_values", "flags", "position" }

--- @param item table an Item instance (or plain row) - mutated in place
-- @return table the same table, for chaining
local function decodeJsonColumns(item)
    if not item then
        return item
    end
    for _, column in ipairs(JSON_COLUMNS) do
        if type(item[column]) == "string" then
            item[column] = fromJSON(item[column]) or nil
        end
    end
    return item
end

-- gm_items (a separate resource) has no access to Model.NULL - it's a
-- plain `{}` table used as a sentinel by REFERENCE identity (see
-- Model.lua's `Model.NULL = {}`), and MTA's triggerEvent copies table
-- arguments across the resource boundary rather than preserving identity,
-- so even a table gm_items claimed was "Model.NULL" would arrive here as
-- a different, unequal table. gm_items instead sends this string
-- constant (see ItemService.lua's dropItem/pickupItem - clearing
-- owner_account_id on drop, clearing position on pickup) and this file
-- translates it to the real Model.NULL right before it reaches QueryBuilder.
local NULL_SENTINEL = "__ITEM_REPOSITORY_NULL__"

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
-- @param callback function(ok: boolean, itemOrError: table|nil|string)
ItemRepository.findById = function(id, callback)
    Item:find(id, function(ok, item)
        callback(ok, ok and decodeJsonColumns(item) or item)
    end)
end

--- @param accountId number
-- @param callback function(ok: boolean, itemsOrError: table|string)
ItemRepository.findByOwnerAccountId = function(accountId, callback)
    Item:where("owner_account_id", accountId):orderBy("created_at", "ASC"):get(function(ok, items)
        if not ok then
            callback(false, items)
            return
        end
        for _, item in ipairs(items) do
            decodeJsonColumns(item)
        end
        callback(true, items)
    end)
end

--- Every ownerless (owner_account_id IS NULL) item, for restoring
--- world-dropped items at resource start - see gm_items/server/
--- ItemService.lua's onResourceStart handler.
-- @param callback function(ok: boolean, itemsOrError: table|string)
ItemRepository.findOwnerless = function(callback)
    Item:query():where("owner_account_id", Model.NULL):get(function(ok, items)
        if not ok then
            callback(false, items)
            return
        end
        for _, item in ipairs(items) do
            decodeJsonColumns(item)
        end
        callback(true, items)
    end)
end

--- @param attributes table column -> value (JSON columns as real Lua tables, not encoded)
-- @param callback function(ok: boolean, itemOrError: table|string)
ItemRepository.create = function(attributes, callback)
    Item:create(encodeJsonColumns(attributes), function(ok, item)
        callback(ok, ok and decodeJsonColumns(item) or item)
    end)
end

--- @param id number
-- @param attributes table column -> value (JSON columns as real Lua tables, not encoded)
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
ItemRepository.update = function(id, attributes, callback)
    Item:query():where("id", id):update(encodeJsonColumns(attributes), callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
ItemRepository.delete = function(id, callback)
    Item:query():where("id", id):delete(callback)
end

-- Deliberately NO flat exported wrappers here - every method above takes
-- a callback, and this project's hard rule (see docs/Architecture.md's
-- "The one hard rule for extending the project") is that a callback must
-- never cross a resource boundary. gm_items (a separate resource) reaches
-- this repository through core/server/ItemService.lua's
-- event-based request/response bridge instead - the exact same pattern
-- VehicleRepository.lua/core/server/database/VehicleService.lua use.
