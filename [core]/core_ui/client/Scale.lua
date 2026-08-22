-- @author: norelock <github.com/notnorelock>
-- @project: districtmta.pl

local baseX = 2048
local screen

getUIScale = function()
    return screen.x < baseX and math.min(2.2, baseX / screen.x) or 1
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    screen  = Vector2(guiGetScreenSize())
end)