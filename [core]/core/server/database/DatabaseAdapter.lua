-- Defines the Database.* contract + adapter registration hook - see
-- docs/DatabaseContract.md.
Database = Database or {}

local currentAdapter = nil

--- Registers the active database adapter implementation.
-- @param adapter table with query/queryOne/execute/insert/transaction functions
Database.registerAdapter = function(adapter)
    assert(type(adapter) == "table", "Database.registerAdapter expects a table")
    assert(type(adapter.query) == "function", "adapter.query must be a function")
    assert(type(adapter.queryOne) == "function", "adapter.queryOne must be a function")
    assert(type(adapter.execute) == "function", "adapter.execute must be a function")
    assert(type(adapter.insert) == "function", "adapter.insert must be a function")
    assert(type(adapter.transaction) == "function", "adapter.transaction must be a function")

    currentAdapter = adapter

    Logger.info("Database", "Adapter registered: " .. (adapter.name or "unnamed"))
end

Database.hasAdapter = function()
    return currentAdapter ~= nil
end

Database.getAdapterName = function()
    return currentAdapter and currentAdapter.name or nil
end

local function requireAdapter()
    if not currentAdapter then
        error("Database.* called before any adapter was registered via Database.registerAdapter")
    end
    return currentAdapter
end

--- Runs a SQL query expected to return zero or more rows.
-- @param sql string MySQL `?`-parameterized SQL (`?` for values, `??` for
--        identifiers - see QueryBuilder.lua's module comment and
--        https://wiki.multitheftauto.com/wiki/DbQuery)
-- @param parameters table|nil positional parameter values, in the exact
--        order their `?`/`??` placeholders appear in `sql`
-- @param callback function(ok: boolean, rowsOrError: table|string)
Database.query = function(sql, parameters, callback)
    requireAdapter().query(sql, parameters or {}, callback)
end

--- Runs a SQL query expected to return zero or one row.
-- @param sql string
-- @param parameters table|nil
-- @param callback function(ok: boolean, rowOrError: table|nil|string)
Database.queryOne = function(sql, parameters, callback)
    requireAdapter().queryOne(sql, parameters or {}, callback)
end

--- Runs a SQL statement that does not return rows (UPDATE/DELETE/DDL).
-- @param sql string
-- @param parameters table|nil
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
Database.execute = function(sql, parameters, callback)
    requireAdapter().execute(sql, parameters or {}, callback)
end

--- @param sql string
-- @param parameters table|nil
-- @param callback function(ok: boolean, affectedRowsOrError: number|string, lastInsertId: number|nil)
Database.insert = function(sql, parameters, callback)
    requireAdapter().insert(sql, parameters or {}, callback)
end

--- Runs a sequence of operations atomically.
-- @param operations function(tx) - receives a transaction-scoped handle exposing
--        query/queryOne/execute/insert with the same signatures as above
-- @param callback function(ok: boolean, resultOrError: any)
Database.transaction = function(operations, callback)
    requireAdapter().transaction(operations, callback)
end
