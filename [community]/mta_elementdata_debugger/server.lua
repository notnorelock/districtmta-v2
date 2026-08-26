addEvent("elementDataDebugger:requestSnapshot", true)
addEventHandler("elementDataDebugger:requestSnapshot", resourceRoot, function()
    if not client or not isElement(client) then
        return
    end

    local data = getAllElementData(client) or {}
    local keys = {}

    for key in pairs(data) do
        keys[#keys + 1] = tostring(key)
    end

    triggerClientEvent(
        client,
        "elementDataDebugger:receiveSnapshot",
        resourceRoot,
        keys
    )
end)
