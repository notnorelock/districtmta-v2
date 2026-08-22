-- Plain "FPS: N" corner readout, reading HUDBase's own frame counter -
-- ported from an older, unrelated project's own Components/fps.lua (MTA
-- class()/instanceof()) to a plain constructor function, matching this
-- project's own style (see HUDComponent.lua's own module comment).
FPSComponent = FPSComponent or {}

local function getUIFont(name)
    return exports.core_ui:getUIFont(name)
end

--- @return table a new FPSComponent instance
FPSComponent.new = function()
    local self = HUDComponent.new()
    self.componentType = "FPSComponent"
    self.position = { x = 10, y = 10 }

    function self:render()
        if not self.visible or not self.hud then
            return
        end

        local fps = math.floor(self.hud.frames)

        dxDrawText(
            "FPS: " .. fps,
            self.position.x, self.position.y, nil, nil,
            tocolor(255, 255, 255, 255), 1, getUIFont("regular_normal"), "left", "top"
        )
    end

    return self
end
