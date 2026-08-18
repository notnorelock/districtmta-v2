-- Active Record base class - see docs/DatabaseContract.md for usage,
-- the column type DSL, and Model.NULL's rationale.
Model = {}
Model.__index = Model

-- Sentinel for "explicitly set this column to SQL NULL" - distinct from
-- Lua `nil`, which means "field absent" (see docs/DatabaseContract.md).
Model.NULL = {}

local function shallowCopy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

--- Defines a new model class backed by `tableName`, registering its schema.
-- @param tableName string
-- @param columns table column definitions, see Schema.lua for the DSL
-- @return table the new model class
function Model:extend(tableName, columns)
    local modelClass = setmetatable({}, { __index = Model })
    modelClass.__index = modelClass
    modelClass._table = tableName
    modelClass._columns = columns
    modelClass._primaryKey = "id"
    modelClass._relations = {}

    for _, column in ipairs(columns) do
        if column.primaryKey then
            modelClass._primaryKey = column.name
        end
    end

    Schema.define(tableName, columns)

    return modelClass
end

--- Wraps a raw database row (plain table keyed by column name) into a
--- model instance. Returns nil if row is nil, so callers can chain
--- straight through a "not found" queryOne result.
-- @param row table|nil
-- @return table|nil instance
function Model:hydrate(row)
    if not row then
        return nil
    end
    return setmetatable(shallowCopy(row), self)
end

local function hydrateAll(modelClass, rows)
    local instances = {}
    for i, row in ipairs(rows) do
        instances[i] = modelClass:hydrate(row)
    end
    return instances
end

--- @return QueryBuilder a fresh query builder scoped to this model's table
function Model:query()
    return QueryBuilder.new(self._table)
end

--- @param id string|number
-- @param callback function(ok: boolean, instanceOrError: table|nil|string)
function Model:find(id, callback)
    self:query():where(self._primaryKey, id):first(function(ok, row)
        if not ok then
            callback(false, row)
            return
        end
        callback(true, self:hydrate(row))
    end)
end

--- Starts a filtered query. Terminal methods (:get/:first/:count) return
--- model instances instead of raw rows, unlike calling QueryBuilder
--- directly.
-- @param column string
-- @param operatorOrValue any
-- @param value any|nil
-- @return table a chainable wrapper around QueryBuilder that hydrates results
function Model:where(column, operatorOrValue, value)
    local modelClass = self
    local builder = self:query():where(column, operatorOrValue, value)

    local wrapper = {}

    function wrapper:where(...)
        builder:where(...)
        return wrapper
    end

    function wrapper:orderBy(...)
        builder:orderBy(...)
        return wrapper
    end

    function wrapper:limit(...)
        builder:limit(...)
        return wrapper
    end

    function wrapper:offset(...)
        builder:offset(...)
        return wrapper
    end

    function wrapper:get(callback)
        builder:get(function(ok, rows)
            if not ok then
                callback(false, rows)
                return
            end
            callback(true, hydrateAll(modelClass, rows))
        end)
    end

    function wrapper:first(callback)
        builder:first(function(ok, row)
            if not ok then
                callback(false, row)
                return
            end
            callback(true, modelClass:hydrate(row))
        end)
    end

    function wrapper:count(callback)
        builder:count(callback)
    end

    function wrapper:exists(callback)
        builder:exists(callback)
    end

    return wrapper
end

--- @param callback function(ok: boolean, instancesOrError: table|string)
function Model:all(callback)
    self:query():get(function(ok, rows)
        if not ok then
            callback(false, rows)
            return
        end
        callback(true, hydrateAll(self, rows))
    end)
end

--- Creates and immediately persists a new instance.
-- @param attributes table column -> value. Omit the primary key - this
--        project's models use an AUTO_INCREMENT "id" column (see
--        Schema.lua), assigned by MySQL and read back via lastInsertId.
-- @param callback function(ok: boolean, instanceOrError: table|string)
function Model:create(attributes, callback)
    local instance = setmetatable(shallowCopy(attributes), self)
    instance:save(function(ok, savedOrError)
        callback(ok, savedOrError)
    end)
end

--- Persists this instance: INSERT if its primary key wasn't already in the
--- table, UPDATE (writing every column) otherwise. Determined by an
--- internal `_persisted` flag, not by re-querying the database.
-- @param callback function(ok: boolean, instanceOrError: table|string)
Model.save = function(instance, callback)
    local modelClass = getmetatable(instance)
    local primaryKey = modelClass._primaryKey

    local data = {}
    for _, column in ipairs(modelClass._columns) do
        if column.name ~= primaryKey and instance[column.name] ~= nil then
            data[column.name] = instance[column.name]
        end
    end

    if instance._persisted then
        modelClass:query():where(primaryKey, instance[primaryKey]):update(data, function(ok, affectedOrError)
            if not ok then
                callback(false, affectedOrError)
                return
            end
            callback(true, instance)
        end)
        return
    end

    modelClass:query():insert(data, function(ok, insertedOrError, lastInsertId)
        if not ok then
            callback(false, insertedOrError)
            return
        end
        instance[primaryKey] = lastInsertId
        instance._persisted = true
        callback(true, instance)
    end)
end

--- Deletes this instance's row.
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
Model.delete = function(instance, callback)
    local modelClass = getmetatable(instance)
    local primaryKey = modelClass._primaryKey

    modelClass:query():where(primaryKey, instance[primaryKey]):delete(callback)
end

--- Declares a has-many relation, generating an instance method
--- `instance:methodName(callback)` that fetches related rows.
-- Example: Account:hasMany("characters", Character, "account_id")
-- generates account:characters(callback).
-- @param methodName string
-- @param relatedModel table the related model class
-- @param foreignKey string column on relatedModel's table pointing back to self
function Model:hasMany(methodName, relatedModel, foreignKey)
    self[methodName] = function(instance, callback)
        relatedModel:where(foreignKey, instance[self._primaryKey]):get(callback)
    end
end

--- Declares a belongs-to relation, generating an instance method
--- `instance:methodName(callback)` that fetches the single owning row.
-- Example: Character:belongsTo("account", Account, "account_id")
-- generates character:account(callback).
-- @param methodName string
-- @param relatedModel table the related model class
-- @param foreignKey string column on self's own table pointing at relatedModel
function Model:belongsTo(methodName, relatedModel, foreignKey)
    self[methodName] = function(instance, callback)
        relatedModel:find(instance[foreignKey], callback)
    end
end
