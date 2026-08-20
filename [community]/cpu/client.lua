---@diagnostic disable: undefined-global
local sx, sy = guiGetScreenSize()
local resStat = false
local serverStats = nil
local serverColumns, serverRows = {}, {}
local font = 'default-bold'

function isAllowed()
    return true
end

addCommandHandler('stat', function()
    if isAllowed() then
        resStat = not resStat
        if resStat then
            outputChatBox('Resource stats enabled', 0, 255, 0, true)
            addEventHandler('onClientRender', root, resStatRender)
            triggerServerEvent('getServerStat', localPlayer)
        else
            outputChatBox('Resource stats disabled', 255, 0, 0, true)
            removeEventHandler('onClientRender', root, resStatRender)
            serverStats = nil
            serverColumns, serverRows = {}, {}
            triggerServerEvent('destroyServerStat', localPlayer)
        end
    end
end)

addEvent('receiveServerStat', true)
addEventHandler('receiveServerStat', root, function(stat1, stat2)
    serverStats = true
    serverColumns, serverRows = stat1, stat2
end)

function getAll(table)
    local all = 0

    for i, v in ipairs(table) do
        if tonumber(string.sub(v[2], 1, string.len(v[2]) - 1)) and v[1] ~= "cpu" then
            all = all + tonumber(string.sub(v[2], 1, string.len(v[2]) - 1))
        end
    end

    return all
end

function resStatRender()
    local x = sx - 400
    if #serverRows == 0 then
        x = sx - 200
    end

    local columns, rows = getPerformanceStats('Lua timing')
    table.insert(rows, {
        '- całość',
        getAll(rows) .. '%',
        color = true
    })

    local height = (20 * #rows)
    local y = sy / 2 - height / 2

    if #serverRows == 0 then
        dxDrawText('Zużycie klienta', x - 10, y - 20, x - 10 + 200, y - 20, tocolor(200, 200, 200, 255), 1, font,
            'center')
    else
        dxDrawText('Zużycie klienta', x - 10, y - 20, x - 10 + 200, y - 20, tocolor(200, 200, 200, 255), 1, font,
            'center')
    end

    for i, row in ipairs(rows) do
        local text = row[1]:sub(0, 15) .. ': ' .. row[2]
        local color = row.color and tocolor(255, 0, 0) or (row[1] and row[1] == "cpu") and tocolor(0, 255, 0) or
        tocolor(200, 200, 200)
        dxDrawRectangle(x - 10, y, 200, 20, i % 2 == 1 and tocolor(125, 125, 125, 205) or tocolor(150, 150, 150, 205))
        dxDrawText(text, x, y, 200, 20, color, 1, font)

        y = y + 20
    end

    if #serverRows ~= 0 then
        local x = sx - 190
        local height = (20 * #serverRows)
        local y = sy / 2 - height / 2

        dxDrawText('Zużycie serwera', x, y - 20, x + 200, y - 20, tocolor(200, 200, 200, 255), 1, font, 'center')

        for i, row in ipairs(serverRows) do
            local text = row[1]:sub(0, 15) .. ': ' .. row[2]
            dxDrawRectangle(x - 10, y, 200, 20, i % 2 == 1 and tocolor(125, 125, 125, 255) or tocolor(150, 150, 150, 255))
            dxDrawText(text, x, y, 200, 20, tocolor(200, 200, 200, 255), 1, font)

            y = y + 20
        end
    end
end
