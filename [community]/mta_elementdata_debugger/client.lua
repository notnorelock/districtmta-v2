local enabled = false
local scrollOffset = 0
local maxVisible = 25
local sx, sy = guiGetScreenSize()

local serverDataKeys = {}
local serverSnapshotReceived = false

local refreshInterval = 2500
local refreshTimer = nil

local function valueToString(value, depth)
    depth = depth or 0

    if depth > 2 then
        return "<max depth>"
    end

    local valueType = type(value)

    if valueType == "table" then
        local parts = {}

        for key, val in pairs(value) do
            parts[#parts + 1] = tostring(key) .. "=" .. valueToString(val, depth + 1)
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end

    if isElement(value) then
        return string.format("<element:%s>", getElementType(value))
    end

    if valueType == "string" then
        return '"' .. value .. '"'
    end

    return tostring(value)
end

local function requestServerSnapshot()
    if not enabled then
        return
    end

    triggerServerEvent("elementDataDebugger:requestSnapshot", resourceRoot)
end

local function startAutoRefresh()
    if isTimer(refreshTimer) then
        killTimer(refreshTimer)
    end

    requestServerSnapshot()

    refreshTimer = setTimer(function()
        requestServerSnapshot()
    end, refreshInterval, 0)
end

local function stopAutoRefresh()
    if isTimer(refreshTimer) then
        killTimer(refreshTimer)
    end

    refreshTimer = nil
end

addEvent("elementDataDebugger:receiveSnapshot", true)
addEventHandler("elementDataDebugger:receiveSnapshot", resourceRoot, function(keys)
    if type(keys) ~= "table" then
        return
    end

    serverDataKeys = {}

    for _, key in ipairs(keys) do
        if type(key) == "string" then
            serverDataKeys[key] = true
        end
    end

    serverSnapshotReceived = true
end)

addCommandHandler("elementdata", function()
    enabled = not enabled
    scrollOffset = 0

    if enabled then
        serverSnapshotReceived = false
        startAutoRefresh()
    else
        stopAutoRefresh()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopAutoRefresh()
end)

addEventHandler("onClientKey", root, function(button, press)
    if not enabled or not press then
        return
    end

    if button == "mouse_wheel_down" then
        scrollOffset = scrollOffset + 1
    elseif button == "mouse_wheel_up" then
        scrollOffset = math.max(0, scrollOffset - 1)
    end
end)

addEventHandler("onClientRender", root, function()
    if not enabled then
        return
    end

    local data = getAllElementData(localPlayer) or {}
    local entries = {}

    for key, value in pairs(data) do
        local source = "CLIENT ONLY"

        if serverSnapshotReceived and serverDataKeys[tostring(key)] then
            source = "SERVER"
        elseif not serverSnapshotReceived then
            source = "UNKNOWN"
        end

        entries[#entries + 1] = {
            key = tostring(key),
            value = valueToString(value),
            valueType = type(value),
            source = source
        }
    end

    table.sort(entries, function(a, b)
        if a.source ~= b.source then
            return a.source < b.source
        end

        return a.key < b.key
    end)

    local panelX = 40
    local panelY = 60
    local panelW = math.min(1050, sx - 80)
    local rowH = 22

    local visibleCount = math.min(maxVisible, #entries)
    local panelH = 92 + visibleCount * rowH

    local maxScroll = math.max(0, #entries - maxVisible)
    scrollOffset = math.min(scrollOffset, maxScroll)

    dxDrawRectangle(
        panelX,
        panelY,
        panelW,
        panelH,
        tocolor(10, 10, 10, 225)
    )

    dxDrawRectangle(
        panelX,
        panelY,
        panelW,
        42,
        tocolor(25, 25, 25, 245)
    )

    dxDrawText(
        "localPlayer element data debugger",
        panelX + 15,
        panelY,
        panelX + panelW,
        panelY + 42,
        tocolor(255, 255, 255),
        1.2,
        "default-bold",
        "left",
        "center"
    )

    dxDrawText(
        string.format("%d entries | auto refresh: %.1fs", #entries, refreshInterval / 1000),
        panelX,
        panelY,
        panelX + panelW - 15,
        panelY + 42,
        tocolor(170, 170, 170),
        1,
        "default",
        "right",
        "center"
    )

    local headerY = panelY + 44

    dxDrawText(
        "KEY",
        panelX + 15,
        headerY,
        panelX + 340,
        headerY + 26,
        tocolor(150, 150, 150),
        0.95,
        "default-bold",
        "left",
        "center"
    )

    dxDrawText(
        "TYPE",
        panelX + 350,
        headerY,
        panelX + 440,
        headerY + 26,
        tocolor(150, 150, 150),
        0.95,
        "default-bold",
        "left",
        "center"
    )

    dxDrawText(
        "SOURCE",
        panelX + 450,
        headerY,
        panelX + 570,
        headerY + 26,
        tocolor(150, 150, 150),
        0.95,
        "default-bold",
        "left",
        "center"
    )

    dxDrawText(
        "VALUE",
        panelX + 580,
        headerY,
        panelX + panelW - 15,
        headerY + 26,
        tocolor(150, 150, 150),
        0.95,
        "default-bold",
        "left",
        "center"
    )

    local startIndex = scrollOffset + 1
    local endIndex = math.min(startIndex + maxVisible - 1, #entries)
    local y = panelY + 70

    for index = startIndex, endIndex do
        local entry = entries[index]

        if index % 2 == 0 then
            dxDrawRectangle(
                panelX + 8,
                y,
                panelW - 16,
                rowH,
                tocolor(255, 255, 255, 8)
            )
        end

        local sourceColor = tocolor(255, 190, 90)

        if entry.source == "SERVER" then
            sourceColor = tocolor(110, 220, 140)
        elseif entry.source == "UNKNOWN" then
            sourceColor = tocolor(180, 180, 180)
        end

        dxDrawText(
            entry.key,
            panelX + 15,
            y,
            panelX + 340,
            y + rowH,
            tocolor(252, 140, 91),
            1,
            "default-bold",
            "left",
            "center",
            true
        )

        dxDrawText(
            entry.valueType,
            panelX + 350,
            y,
            panelX + 440,
            y + rowH,
            tocolor(160, 160, 160),
            1,
            "default",
            "left",
            "center"
        )

        dxDrawText(
            entry.source,
            panelX + 450,
            y,
            panelX + 570,
            y + rowH,
            sourceColor,
            1,
            "default-bold",
            "left",
            "center"
        )

        dxDrawText(
            entry.value,
            panelX + 580,
            y,
            panelX + panelW - 15,
            y + rowH,
            tocolor(230, 230, 230),
            1,
            "default",
            "left",
            "center",
            true
        )

        y = y + rowH
    end
end)
