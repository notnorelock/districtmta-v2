-- Connects MySqlAdapter, then runs Schema.migrate() and fires
-- Events.DATABASE_READY once it finishes - see docs/DatabaseContract.md.
addEvent(Events.DATABASE_READY, true)

if MySqlAdapter.connect() then
    Database.registerAdapter(MySqlAdapter)
    Schema.migrate(function()
        triggerEvent(Events.DATABASE_READY, resourceRoot)
    end)
else
    Logger.error("Database", "MySqlAdapter failed to connect - no database adapter is active, every Database.* call will error")
end