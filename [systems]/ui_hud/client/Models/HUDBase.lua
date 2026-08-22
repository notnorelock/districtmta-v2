-- Owns the component list (Radar/FPS/Notifications) and drives their
-- render()/update() every frame - ported from an older, unrelated
-- project's own base.lua (MTA class()/instanceof()) to a plain
-- constructor function, matching this project's own style (see
-- HUDComponent.lua's own module comment for the same reasoning). A
-- single HUDBase instance is created once by Bootstrap.lua.
HUDBase = HUDBase or {}

--- @return table a new HUD instance
HUDBase.new = function()
    local self = {
        frames = 0,
        framesNextTick = 0,
        components = {},
    }

    --- @param component table a HUDComponent.new()-shaped instance, with
    --        component.componentType set by the caller (e.g. "RadarComponent")
    --- @return table|false the component, for chaining - false if `component`
    --         doesn't look like a component (no componentType)
    function self:addComponent(component)
        if type(component) ~= "table" or not component.componentType then
            return false
        end
        component:setHUD(self)
        self.components[#self.components + 1] = component
        return component
    end

    --- @param component table
    -- @return boolean true if it was actually in this HUD
    function self:removeComponent(component)
        for i, existing in ipairs(self.components) do
            if existing == component then
                table.remove(self.components, i)
                return true
            end
        end
        return false
    end

    --- @param componentType string e.g. "RadarComponent"
    -- @return table|false
    function self:getComponent(componentType)
        for _, component in ipairs(self.components) do
            if component.componentType == componentType then
                return component
            end
        end
        return false
    end

    local function handleClientRender()
        for _, component in ipairs(self.components) do
            if component:isVisible() then
                component:render()
            end
        end
    end

    local function handleClientPreRender(msSinceLastFrame)
        local now = getTickCount()

        if now >= self.framesNextTick then
            self.frames = (1 / msSinceLastFrame) * 1000
            self.framesNextTick = now + 1000
        end

        for _, component in ipairs(self.components) do
            component:update(msSinceLastFrame)
        end
    end

    addEventHandler("onClientRender", root, handleClientRender)
    addEventHandler("onClientPreRender", root, handleClientPreRender)

    function self:destroy()
        removeEventHandler("onClientRender", root, handleClientRender)
        removeEventHandler("onClientPreRender", root, handleClientPreRender)
        for _, component in ipairs(self.components) do
            component:destroy()
        end
        self.components = {}
    end

    return self
end
