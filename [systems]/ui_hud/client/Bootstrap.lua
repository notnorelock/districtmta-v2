-- Wires up the native dxDraw HUD pieces (radar/FPS/notifications) - a
-- SEPARATE rendering system from HudState.lua's own CEF-pushed health/
-- hunger/thirst/voice HUD in this same resource, not a replacement for
-- it (see this file's own components' module comments on why each one
-- exists alongside a CEF equivalent, where one already does). Ported
-- from an older, unrelated project's own bootstrap.lua.
local hud

addEventHandler("onClientResourceStart", resourceRoot, function()
    hud = HUDBase.new()

    hud:addComponent(FPSComponent.new())
    hud:addComponent(RadarComponent.new())
    hud:addComponent(NotificationsComponent.new())
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if hud then
        hud:destroy()
        hud = nil
    end
end)

-- NotificationService.send/.broadcast (core) -> ui_hud/server/
-- NotificationBridge.lua -> Events.NOTIFICATION_SHOW -> here -> re-fired
-- as "onClientShowNotification", NotificationsComponent's own single real
-- entry point (also used directly by its own /test-noti* commands and by
-- the frontend's mta.notify("onClientShowNotification", ...) calls) -
-- kept as ONE trigger path into the component rather than this handler
-- calling notifications:show() itself as a second one.
-- Enums.NotificationType's keys map 1:1 onto NotificationsComponent's own
-- category keys.
local NOTIFICATION_TYPE_TO_CATEGORY = {
    success = "success",
    error = "error",
    info = "info",
    warning = "warning",
}

addEvent(Events.NOTIFICATION_SHOW, true)
addEventHandler(Events.NOTIFICATION_SHOW, resourceRoot, function(notificationType, title, message)
    local category = NOTIFICATION_TYPE_TO_CATEGORY[notificationType] or "notification"
    -- title is nil more often than not now (see NotificationService.send's
    -- own comment) - properties.title left nil here just means
    -- NotificationsComponent:show() falls back to the category's own
    -- default heading, exactly as intended.
    triggerEvent("onClientShowNotification", root, category, message or title, { title = title })
end)

local DEFAULT_TOGGLE_DURATION = 500

--- @param visible boolean
-- @return boolean the radar's new visibility (false if the radar component isn't ready yet)
function setRadarVisible(visible)
    if not hud then return false end
    local radar = hud:getComponent("RadarComponent")
    if not radar then return false end

    if visible then
        radar:show(DEFAULT_TOGGLE_DURATION)
    else
        radar:hide(DEFAULT_TOGGLE_DURATION)
    end

    return radar:isVisible()
end

--- @return boolean
function isRadarVisible()
    if not hud then return false end
    local radar = hud:getComponent("RadarComponent")
    if not radar then return false end

    return radar:isVisible()
end

--- @return number, number, number, number|false x, y, width, height - false if the radar component isn't ready yet
function getRadarPosition()
    if not hud then return false end
    local radar = hud:getComponent("RadarComponent")
    if not radar then return false end

    return radar:getPosition()
end
