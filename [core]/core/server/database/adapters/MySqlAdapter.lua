-- Real MySQL adapter backing Database.* - see docs/DatabaseContract.md
-- for the wire contract and the dbPoll/setTimer gotchas below.
MySqlAdapter = {
    name = "MySqlAdapter (MySQL, via MTA dbConnect)",
}

local connection = nil

local POLL_RETRY_MS = 15

--- Connects using the MYSQL_* resource settings (see meta.xml). Called once
--- from MySqlAdapterBootstrap.lua.
-- @return boolean ok
MySqlAdapter.connect = function()
    local host = get("MYSQL_HOST") or "127.0.0.1"
    local port = get("MYSQL_PORT") or "3306"
    local database = get("MYSQL_DATABASE") or "district"
    local username = get("MYSQL_USERNAME") or "root"
    local password = get("MYSQL_PASSWORD") or ""
    local charset = get("MYSQL_CHARSET") or "utf8mb4"

    local connectionString = ("dbname=%s;host=%s;port=%s;charset=%s"):format(database, host, port, charset)

    connection = dbConnect("mysql", connectionString, username, password, "autoreconnect=1;log=1")

    if not connection then
        Logger.error("MySqlAdapter", "dbConnect failed", { host = host, port = port, database = database })
        return false
    end

    Logger.info("MySqlAdapter", "Connected", { host = host, port = port, database = database })
    return true
end

MySqlAdapter.isConnected = function()
    return connection ~= nil
end

--- Polls a query handle until it resolves, without blocking the server
--- (unlike dbPoll(qh, -1)). Retries every POLL_RETRY_MS via setTimer -
--- onResult is captured in a closure, not passed through setTimer's own
--- arguments (see docs/DatabaseContract.md's callback-timing gotchas).
-- @param queryHandle handle
-- @param onResult function(result: table|false, numAffectedRows: number|nil, lastInsertId: number|nil, errorMessage: string|nil)
local function pollUntilReady(queryHandle, onResult)
    local function poll()
        local result, secondValue, thirdValue = dbPoll(queryHandle, 0)

        if result == nil then
            setTimer(poll, POLL_RETRY_MS, 1)
            return
        end

        if result == false then
            local errorCode, errorMessage = secondValue, thirdValue
            onResult(false, nil, nil, tostring(errorMessage or errorCode or "unknown MySQL error"))
            return
        end

        local numAffectedRows, lastInsertId = secondValue, thirdValue
        onResult(result, numAffectedRows, lastInsertId, nil)
    end

    poll()
end

--- Runs a query and returns rows (used for both `query` and `queryOne` -
--- queryOne just takes the first row).
local function runQuery(sql, parameters, callback)
    if not connection then
        callback(false, "MySqlAdapter: not connected")
        return
    end

    local queryHandle = dbQuery(connection, sql, unpack(parameters))

    if not queryHandle then
        callback(false, "MySqlAdapter: dbQuery returned false (invalid connection or malformed query)")
        return
    end

    pollUntilReady(queryHandle, function(result, numAffectedRows, lastInsertId, errorMessage)
        if not result then
            Logger.error("MySqlAdapter", "Query failed", { sql = sql, error = errorMessage })
            callback(false, "MySqlAdapter: query failed")
            return
        end

        callback(true, result, numAffectedRows, lastInsertId)
    end)
end

MySqlAdapter.query = function(sql, parameters, callback)
    runQuery(sql, parameters, function(ok, rowsOrError)
        callback(ok, rowsOrError)
    end)
end

MySqlAdapter.queryOne = function(sql, parameters, callback)
    runQuery(sql, parameters, function(ok, rowsOrError)
        if not ok then
            callback(false, rowsOrError)
            return
        end

        callback(true, rowsOrError[1])
    end)
end

MySqlAdapter.execute = function(sql, parameters, callback)
    runQuery(sql, parameters, function(ok, rowsOrError, numAffectedRows)
        if not ok then
            callback(false, rowsOrError)
            return
        end

        callback(true, numAffectedRows or 0)
    end)
end

-- @param sql string INSERT statement
-- @param parameters table
-- @param callback function(ok, affectedRowsOrError, lastInsertId)
MySqlAdapter.insert = function(sql, parameters, callback)
    runQuery(sql, parameters, function(ok, rowsOrError, numAffectedRows, lastInsertId)
        if not ok then
            callback(false, rowsOrError)
            return
        end

        callback(true, numAffectedRows or 0, lastInsertId)
    end)
end

--- Manual START TRANSACTION/COMMIT/ROLLBACK - MTA has no transaction API.
-- @param operations function(tx)
-- @param callback function(ok, resultOrError)
MySqlAdapter.transaction = function(operations, callback)
    if not connection then
        callback(false, "MySqlAdapter: not connected")
        return
    end

    local tx = {
        query = MySqlAdapter.query,
        queryOne = MySqlAdapter.queryOne,
        execute = MySqlAdapter.execute,
        insert = MySqlAdapter.insert,
    }

    runQuery("START TRANSACTION", {}, function(startOk, startError)
        if not startOk then
            callback(false, startError)
            return
        end

        local ok, result = pcall(operations, tx)

        if not ok then
            runQuery("ROLLBACK", {}, function()
                Logger.error("MySqlAdapter", "Transaction rolled back", { error = tostring(result) })
                callback(false, tostring(result))
            end)
            return
        end

        runQuery("COMMIT", {}, function(commitOk, commitError)
            if not commitOk then
                callback(false, commitError)
                return
            end

            callback(true, result)
        end)
    end)
end

addEventHandler("onResourceStop", resourceRoot, function()
    if connection then
        setTimer(destroyElement, 0, 1, connection)
        connection = nil
    end
end)
