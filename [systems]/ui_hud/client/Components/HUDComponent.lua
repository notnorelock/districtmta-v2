-- Base "component" shape every HUD piece (Radar/FPS/Notifications) is
-- built from - ported from an older, unrelated project's own
-- Models/component.lua (MTA class()/instanceof()) to a plain constructor
-- function returning a table, matching this project's own style. A
-- "component" here is just a table with these fields/methods mixed in via
-- HUDComponent.new()'s shallow copy - render()/update() are meant to be
-- overwritten per concrete component (Radar.lua etc. do so directly on
-- the instance after calling HUDComponent.new()).
HUDComponent = HUDComponent or {}

--- @return table a new component instance with every method below as its
--         own field (not metatable-inherited - see this file's own
--         module comment on why: a concrete component overwrites
--         render()/update() directly on the instance).
HUDComponent.new = function()
    local self = {
        visible = true,
        position = { x = 0, y = 0 },
        hud = nil,
        animations = {},
        alpha = 1,
        scale = 1,
        color = { r = 255, g = 255, b = 255, a = 255 },
    }

    function self:setHUD(hud)
        self.hud = hud
    end

    function self:setPosition(x, y)
        self.position = { x = x, y = y }
    end

    function self:setVisible(visible)
        self.visible = visible
    end

    function self:isVisible()
        return self.visible
    end

    function self:setAlpha(alpha)
        self.alpha = math.max(0, math.min(1, alpha))
    end

    function self:getAlpha()
        return self.alpha
    end

    function self:setScale(scale)
        self.scale = scale
    end

    function self:getScale()
        return self.scale
    end

    function self:animatePosition(toX, toY, easing, duration, onEnd)
        local fromX, fromY = self.position.x, self.position.y

        local animX = AnimationManager.create(fromX, toX, easing, duration, function(value)
            self.position.x = value
        end)
        local animY = AnimationManager.create(fromY, toY, easing, duration, function(value)
            self.position.y = value
        end, onEnd)

        self.animations[#self.animations + 1] = animX
        self.animations[#self.animations + 1] = animY
        return animX, animY
    end

    function self:animateAlpha(toAlpha, easing, duration, onEnd)
        local anim = AnimationManager.create(self.alpha, toAlpha, easing, duration, function(value)
            self:setAlpha(value)
        end, onEnd)
        self.animations[#self.animations + 1] = anim
        return anim
    end

    function self:animateScale(toScale, easing, duration, onEnd)
        local anim = AnimationManager.create(self.scale, toScale, easing, duration, function(value)
            self.scale = value
        end, onEnd)
        self.animations[#self.animations + 1] = anim
        return anim
    end

    function self:fadeIn(duration, onEnd)
        self.alpha = 0
        self.visible = true
        return self:animateAlpha(1, "Linear", duration or 500, onEnd)
    end

    function self:fadeOut(duration, onEnd)
        return self:animateAlpha(0, "Linear", duration or 500, function()
            self.visible = false
            if onEnd then onEnd() end
        end)
    end

    function self:stopColorAnimations()
        for i = #self.animations, 1, -1 do
            local anim = self.animations[i]
            if anim.isColorAnimation then
                AnimationManager.remove(anim)
                table.remove(self.animations, i)
            end
        end
    end

    function self:animateColor(toR, toG, toB, toA, easing, duration, onEnd)
        self:stopColorAnimations()

        local fromR, fromG, fromB = self.color.r, self.color.g, self.color.b
        local fromA = self.color.a or 255
        toA = toA or fromA

        local animR = AnimationManager.create(fromR, toR, easing, duration, function(value) self.color.r = value end)
        local animG = AnimationManager.create(fromG, toG, easing, duration, function(value) self.color.g = value end)
        local animB = AnimationManager.create(fromB, toB, easing, duration, function(value) self.color.b = value end)
        local animA = AnimationManager.create(fromA, toA, easing, duration, function(value) self.color.a = value end, onEnd)

        animR.isColorAnimation = true
        animG.isColorAnimation = true
        animB.isColorAnimation = true
        animA.isColorAnimation = true

        self.animations[#self.animations + 1] = animR
        self.animations[#self.animations + 1] = animG
        self.animations[#self.animations + 1] = animB
        self.animations[#self.animations + 1] = animA
        return animR, animG, animB, animA
    end

    function self:getColor()
        return tocolor(self.color.r, self.color.g, self.color.b, self.color.a)
    end

    function self:setColor(r, g, b, a)
        self.color.r = r
        self.color.g = g
        self.color.b = b
        self.color.a = a or 255
    end

    function self:stopAnimations()
        for _, anim in ipairs(self.animations) do
            AnimationManager.remove(anim)
        end
        self.animations = {}
    end

    -- Overridden per concrete component (Radar/FPS/Notifications each
    -- assign their own render/update directly on the instance after
    -- calling HUDComponent.new()).
    function self:render() end
    function self:update(msSinceLastFrame) end

    function self:destroy()
        self:stopAnimations()
        self.hud = nil
    end

    return self
end
