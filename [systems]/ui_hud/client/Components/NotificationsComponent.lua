-- Native dxDraw toast notifications (a stack of cards, bottom-right) -
-- ported from an older, unrelated project's own Components/
-- notifications.lua (MTA class()/instanceof()) to a plain constructor
-- function, matching this project's own style (see HUDComponent.lua's own
-- module comment).
--
-- The project's ONLY notification toast system - the former CEF one
-- (packages/ui/src/features/notifications/, driven by
-- core's NotificationService.send/broadcast via a PUSH_NOTIFICATION_CREATED
-- CEF push) was removed once this native one existed; NotificationService
-- now fires directly into this component (see Bootstrap.lua's
-- Events.NOTIFICATION_SHOW handler, which maps NotificationService's
-- type ("success"/"error"/"info"/"warning") onto this component's own
-- category keys ("warn", not "warning") and calls self:show()). Locally,
-- anything client-side can also trigger a toast directly via
-- triggerEvent("onClientShowNotification", root, category, text, properties)
-- - see this file's own /test-noti* commands below for the exact shape.
NotificationsComponent = NotificationsComponent or {}

local function getUIFont(name)
    return exports.core_ui:getUIFont(name)
end

local function getUIScale()
    return exports.core_ui:getUIScale() or 1
end

--- @return table a new NotificationsComponent instance
NotificationsComponent.new = function()
    local self = HUDComponent.new()
    local zoom = getUIScale()
    local screenW, screenH = guiGetScreenSize()

    self.componentType = "NotificationsComponent"
    self.visible = true

    self.notifications = {}

    self.maxVisible = 6
    self.defaultTime = 8000
    self.notificationInTime = 400
    self.notificationOffsetY = 1.12
    self.textWidthMultiplier = 0.815
    self.notificationOffsetAnimTime = 300

    self.position = {
        x = 552 / zoom,
        y = screenH / 1.2,
        w = 400 / zoom,
        h = 65 / zoom,
    }

    self.defaultY = screenH / 1.2
    self.useRadarPosition = false

    self.categories = {
        info = { text = "Informacja", color = { 63, 113, 171 } },
        error = { text = "Błąd", color = { 205, 53, 53 } },
        warning = { text = "Ostrzeżenie", color = { 205, 151, 70 } },
        success = { text = "Sukces", color = { 97, 168, 100 } },
        notification = { text = "Powiadomienie", color = { 255, 255, 255 } },
    }

    self.textures = {}

    function self:loadResources()
        self.textures.info = dxCreateTexture("assets/notifications/info.png")
        self.textures.error = dxCreateTexture("assets/notifications/error.png")
        self.textures.warning = dxCreateTexture("assets/notifications/warning.png")
        self.textures.success = dxCreateTexture("assets/notifications/success.png")
        self.textures.background = dxCreateTexture("assets/notifications/background.png")
    end

    local function onShowNotification(...)
        self:show(...)
    end

    function self:setupEvents()
        addEvent("onClientShowNotification", true)
        addEventHandler("onClientShowNotification", root, onShowNotification)
    end

    function self:updateRadarPosition()
        if not self.hud then return end

        local radarComponent = self.hud:getComponent("RadarComponent")
        if not radarComponent then return end

        local radarVisible = radarComponent:isVisible()

        if radarVisible then
            local x, _, w, h = radarComponent:getPosition()
            if not self.useRadarPosition then
                self.position.x = x
                self.position.y = (self.position.y - h + 35)
                self.position.w = w
                self.useRadarPosition = true
            end
        else
            if self.useRadarPosition then
                self.position.y = self.defaultY
                self.useRadarPosition = false
            end
        end
    end

    function self:getVisibleCount()
        local count = 0
        for _, notification in ipairs(self.notifications) do
            if not notification.hidden and not notification.finished then
                count = count + 1
            end
        end
        return count
    end

    function self:recalculateOffsets(mode)
        if #self.notifications <= 1 then return end

        if mode == "in" then
            local activeNotifications = {}
            for _, notification in ipairs(self.notifications) do
                if not notification.hidden and not notification.finished then
                    activeNotifications[#activeNotifications + 1] = notification
                end
            end

            local totalOffsetY = (#activeNotifications - 1) * self.position.h * self.notificationOffsetY

            for i = 1, #self.notifications - 1 do
                local notification = self.notifications[i]
                if not notification.hidden and not notification.finished then
                    notification:animateOffsetY(totalOffsetY, self.notificationOffsetAnimTime)
                    totalOffsetY = totalOffsetY - self.position.h * self.notificationOffsetY
                end
            end

            local newNotification = self.notifications[#self.notifications]
            newNotification:animateOffsetY(totalOffsetY, self.notificationOffsetAnimTime)
        elseif mode == "out" then
            local activeNotifications = {}
            for _, notification in ipairs(self.notifications) do
                if not notification.hidden and not notification.finished then
                    activeNotifications[#activeNotifications + 1] = notification
                end
            end

            table.sort(activeNotifications, function(a, b)
                return a.offsetY < b.offsetY
            end)

            local totalOffsetY = 0
            for _, notification in ipairs(activeNotifications) do
                notification:animateOffsetY(totalOffsetY, self.notificationOffsetAnimTime)
                totalOffsetY = totalOffsetY + self.position.h * self.notificationOffsetY
            end
        end
    end

    --- @param category string one of self.categories's own keys
    -- @param text string
    -- @param properties table|nil { time, icon, color, title, glow, sound, destroyable, indeterminated, indeterminatedWidth }
    -- @return table|false the created Notification, or false if category/text were invalid
    function self:show(category, text, properties)
        if not self.categories[category] or type(text) ~= "string" then
            return false
        end

        if self:getVisibleCount() >= self.maxVisible then
            for _, notification in ipairs(self.notifications) do
                if notification.properties.destroyable and not notification.hidden and not notification.finished then
                    notification.hidden = true
                    notification.finished = true
                    self:recalculateOffsets("in")
                    break
                end
            end
        end

        properties = properties or {}
        properties.time = properties.time or self.defaultTime
        properties.icon = properties.icon or "default"
        properties.color = properties.color or "default"
        properties.title = properties.title or self.categories[category].text
        properties.glow = properties.glow ~= nil and properties.glow or false
        properties.sound = properties.sound ~= nil and properties.sound or true
        properties.destroyable = properties.destroyable ~= nil and properties.destroyable or true
        properties.indeterminated = properties.indeterminated or false
        properties.indeterminatedWidth = properties.indeterminatedWidth or 1

        if properties.sound then
            local soundPath = string.format("assets/notifications/%s.wav", category)
            if fileExists(soundPath) then
                setSoundVolume(playSound(soundPath), 0.7)
            end
        end

        local textScale = Helpers.calculateTextScale(text)
        local lines = Helpers.wordWrap(text, self.position.w * self.textWidthMultiplier, textScale, getUIFont("semibold_normal"), false)

        local notification = Notification.new(category, text, properties)
        notification.title = properties.title
        notification.icon = properties.icon == "default" and self.textures[category] or properties.icon
        notification.color = properties.color == "default" and self.categories[category].color or properties.color
        notification.textScale = textScale - 0.35
        notification.lines = #lines
        notification.offsetX = self.position.w * 2

        self.notifications[#self.notifications + 1] = notification

        notification:animateIn(self.notificationInTime)

        if properties.destroyable or properties.time ~= -1 then
            notification:startTimer(properties.time, function()
                self:remove(notification)
            end)
        end

        self:recalculateOffsets("in")

        outputDebugString(string.format("[%s] %s", properties.title, text))

        return notification
    end

    function self:remove(notification)
        if notification.hiding or notification.hidden or notification.finished then
            return
        end

        notification.hiding = true
        notification:animateOut(self.notificationInTime, self.position.w * 2, function()
            self:recalculateOffsets("out")
        end)
    end

    function self:drawNotification(notification)
        local pos = self.position
        local offsetX, offsetY = notification.offsetX, notification.offsetY
        local posX, posY = pos.x - offsetX, pos.y - offsetY

        if self.textures.background then
            dxDrawImage(posX, posY, pos.w, pos.h, self.textures.background, 0, 0, 0,
                tocolor(255, 255, 255, 255 * notification.alpha))
        end

        local ix, iy, iw, ih, io = 15 / zoom, (pos.h * 0.485) / 2, pos.h * 0.52, pos.h * 0.52, 45 / zoom

        if isElement(notification.icon) then
            dxDrawImage(posX + ix, posY + iy, iw, ih, notification.icon, 0, 0, 0,
                tocolor(255, 255, 255, 255 * notification.alpha))
        else
            ix, iy, io = 0, 0, 20 / zoom
        end

        local textX, textY, textW, textH = posX + ix + io, posY, pos.w * self.textWidthMultiplier, pos.h
        local color = notification.color

        dxDrawText(notification.text, textX, textY, textX + textW, textY + textH,
            tocolor(240, 240, 240, 255 * notification.alpha),
            notification.textScale or 1, getUIFont("semibold_normal"), "left", "center", false, true)

        -- local barWidth = not notification.properties.indeterminated
        --     and math.max(1, pos.w * notification.timeProgress)
        --     or math.max(1, pos.w * notification.properties.indeterminatedWidth)
        -- local progress = (getTickCount() - notification.tick) / 1000
        -- local barAlpha = 255 * notification.alpha *
        --     (notification.properties.glow and interpolateBetween(1, 0, 0, 0.5, 0, 0, progress, "SineCurve") or 1)
        -- dxDrawRectangle(posX, posY + pos.h - 2.5, barWidth, 2.5,
        --     tocolor(color[1], color[2], color[3], barAlpha))
        -- dxDrawRectangle(posX, posY + pos.h - 2.5, pos.w, 2.5,
        --     tocolor(color[1], color[2], color[3], 255 * notification.alpha * 0.15))
    end

    function self:cleanupFinished()
        local allFinished = true
        for _, notification in ipairs(self.notifications) do
            if not notification.hidden or not notification.finished then
                allFinished = false
                break
            end
        end

        if allFinished and #self.notifications > 0 then
            for _, notification in ipairs(self.notifications) do
                notification:destroy()
            end
            self.notifications = {}
        end
    end

    function self:render()
        if not self.visible then return end

        self:updateRadarPosition()
        self:cleanupFinished()

        for _, notification in ipairs(self.notifications) do
            if not notification.hidden and not notification.finished then
                self:drawNotification(notification)
            end
        end
    end

    local baseDestroy = self.destroy
    function self:destroy()
        for _, notification in ipairs(self.notifications) do
            notification:destroy()
        end
        self.notifications = {}

        for k, v in pairs(self.textures) do
            if isElement(v) then
                destroyElement(v)
            end
        end
        self.textures = {}

        removeEventHandler("onClientShowNotification", root, onShowNotification)

        baseDestroy(self)
    end

    self:loadResources()
    self:setupEvents()

    self.position.x = self.position.x - self.position.w - 120 / zoom

    return self
end

-- Test commands - kept from the ported original for manually exercising
-- every code path (limit/spam/persistent/custom) without needing a real
-- trigger wired up yet.
addCommandHandler("test-noti", function()
    local categories = { "info", "warning", "success", "error", "notification" }
    local messages = {
        "Testowe powiadomienie - to jest przykładowa wiadomość",
        "Uwaga! Coś ważnego się dzieje",
        "Operacja zakończona sukcesem!",
        "Wystąpił błąd podczas wykonywania operacji",
        "Masz nowe powiadomienie",
    }

    for i, category in ipairs(categories) do
        setTimer(function()
            triggerEvent("onClientShowNotification", root, category, messages[i], {
                time = 8000 + (i * 1000),
                glow = true,
            })
        end, (i - 1) * 1000, 1)
    end

    outputChatBox("Testowanie wszystkich typów notyfikacji...", 0, 255, 0)
end)

addCommandHandler("test-noti-spam", function()
    for i = 1, 10 do
        setTimer(function()
            triggerEvent("onClientShowNotification", root, "info", "Notyfikacja #" .. i, {
                time = 5000,
                glow = false,
            })
        end, (i - 1) * 200, 1)
    end

    outputChatBox("Testowanie limitu notyfikacji (spam)...", 0, 255, 0)
end)

addCommandHandler("test-noti-persistent", function()
    triggerEvent("onClientShowNotification", root, "notification", "To powiadomienie nie zniknie samo!", {
        time = -1,
        destroyable = false,
        indeterminated = true,
        glow = true,
        title = "Ważna informacja",
    })

    outputChatBox("Utworzono trwałe powiadomienie. Użyj /test-noti-clear aby wyczyścić.", 0, 255, 0)
end)

addCommandHandler("test-noti-custom", function(cmd, ...)
    local message = table.concat({ ... }, " ")
    if message == "" then
        outputChatBox("Użycie: /test-noti-custom <wiadomość>", 255, 0, 0)
        return
    end

    triggerEvent("onClientShowNotification", root, "success", message, {
        time = 10000,
        glow = true,
    })
end)
