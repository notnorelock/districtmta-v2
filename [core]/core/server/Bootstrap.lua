local function assertDependency(globalName, resourceName)
    if not _G[globalName] then
        outputServerLog(string.format(
            "[ERROR] [core] Missing dependency '%s' - is resource '%s' started before core?",
            globalName, resourceName
        ))
        return false
    end
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    local ok = true
    ok = assertDependency("Events", "core_shared") and ok
    ok = assertDependency("ErrorCodes", "core_shared") and ok

    if ok then
        Logger.info("core", "Bootstrap complete", {
            resource = getResourceName(getThisResource()),
            databaseAdapter = Database.getAdapterName() or "none registered",
        })
    else
        Logger.error("core", "Bootstrap completed with missing dependencies - check meta.xml include order")
    end
end)
