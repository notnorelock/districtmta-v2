-- A single toast card's own transient state (alpha/offset/progress) and
-- its animate-in/out/reflow tweens - ported from an older, unrelated
-- project's own Models/notification.lua (MTA class()/instanceof()) to a
-- plain constructor function, matching this project's own style (see
-- HUDComponent.lua's own module comment). Owned/drawn by
-- NotificationsComponent.lua, never rendered on its own.
Notification = Notification or {}

--- @param category string one of NotificationsComponent's own categories key ("info"/"warn"/"error"/"success"/"notification")
-- @param text string
-- @param properties table see NotificationsComponent.show's own defaulting
-- @return table a new Notification instance
Notification.new = function(category, text, properties)
    local self = {
        category = category,
        text = text,
        properties = properties or {},

        alpha = 0,
        offsetX = 0,
        offsetY = 0,
        timeProgress = 1,

        hidden = false,
        finished = false,
        hiding = false,

        tick = getTickCount(),

        animations = {},
    }

    function self:animateIn(duration, onEnd)
        local alphaAnim = AnimationManager.create(0, 1, "InOutQuad", duration, function(value)
            self.alpha = value
        end)

        local posAnim = AnimationManager.create(self.offsetX, 0, "InOutQuad", duration, function(value)
            self.offsetX = value
        end, onEnd)

        self.animations[#self.animations + 1] = alphaAnim
        self.animations[#self.animations + 1] = posAnim
        return alphaAnim, posAnim
    end

    function self:animateOut(duration, slideDistance, onEnd)
        local alphaAnim = AnimationManager.create(self.alpha, 0, "InOutQuad", duration, function(value)
            self.alpha = value
        end, function()
            self.hidden = true
            self.finished = true
            if onEnd then onEnd() end
        end)

        local posAnim = AnimationManager.create(self.offsetX, slideDistance, "InOutQuad", duration * 1.5, function(value)
            self.offsetX = value
        end)

        self.animations[#self.animations + 1] = alphaAnim
        self.animations[#self.animations + 1] = posAnim
        return alphaAnim, posAnim
    end

    function self:animateOffsetY(toY, duration)
        for i = #self.animations, 1, -1 do
            if self.animations[i].isOffsetYAnim then
                AnimationManager.remove(self.animations[i])
                table.remove(self.animations, i)
            end
        end

        local anim = AnimationManager.create(self.offsetY, toY, "InOutQuad", duration, function(value)
            self.offsetY = value
        end)
        anim.isOffsetYAnim = true

        self.animations[#self.animations + 1] = anim
        return anim
    end

    function self:startTimer(duration, onEnd)
        local timerAnim = AnimationManager.create(1, 0, "Linear", duration, function(value)
            self.timeProgress = value
        end, onEnd)

        self.animations[#self.animations + 1] = timerAnim
        return timerAnim
    end

    function self:stopAnimations()
        for _, anim in ipairs(self.animations) do
            AnimationManager.remove(anim)
        end
        self.animations = {}
    end

    function self:destroy()
        self:stopAnimations()
    end

    return self
end
