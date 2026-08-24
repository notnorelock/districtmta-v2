local IS_SERVER = isElement(localPlayer)

if IS_SERVER then
    addCommandHandler("gpos", function()
        local x, y, z = getElementPosition(localPlayer)
        local rx, ry, rz = getElementRotation(localPlayer)
        local interior = getElementInterior(localPlayer)
        local dimension = getElementDimension(localPlayer)

        outputChatBox(" ")
        outputChatBox(string.format("pozycja klient: x=%.2f,y=%.2f,z=%.2f", x, y, z))
        outputChatBox(string.format("rotacja: %.2f | interior: %d | dim: %d", rz, interior, dimension))
        outputChatBox(" ")
    end)
else
    addCommandHandler("gpos", function(player)
        local x, y, z = getElementPosition(player)
        local rx, ry, rz = getElementRotation(player)
        local interior = getElementInterior(player)
        local dimension = getElementDimension(player)

        outputChatBox(" ", player)
        outputChatBox(string.format("pozycja serwer: x=%.2f,y=%.2f,z=%.2f", x, y, z), player)
        outputChatBox(string.format("rotacja: %.2f | interior: %d | dim: %d", rz, interior, dimension), player)
        outputChatBox(" ", player)
    end)
end