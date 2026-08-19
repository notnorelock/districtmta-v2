local onDuty = false

local keys = {
    {
        key = "F6",
        cmd = "apanel"
    },
    {
        key = "F7",
        cmd = "reports"
    },
    {
        key = "J",
        cmd = "jetpack"
    }
}

local function bindShortcuts()
    if onDuty then
        return
    end
    onDuty = true

    for k, v in ipairs(keys) do
        bindKey(v.key, "down", v.cmd)
    end
end

local function unbindShortcuts()
    if not onDuty then
        return
    end
    onDuty = false
    
    for k, v in ipairs(keys) do
        unbindKey(v.key, "down", v.cmd)
    end
end

addEvent(Events.ADMIN_DUTY_CHANGED, true)
addEventHandler(Events.ADMIN_DUTY_CHANGED, root, function(isOnDuty)
    if isOnDuty then
        bindShortcuts()
    else
        unbindShortcuts()
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent(Events.ADMIN_REQUEST_DUTY_STATUS, resourceRoot)
end)

