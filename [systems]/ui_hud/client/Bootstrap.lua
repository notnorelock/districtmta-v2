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

-- NotificationService.send/.broadcast (core) -> Events.NOTIFICATION_SHOW ->
-- here. NotificationsComponent's own categories use "warn", not "warning"
-- (Enums.NotificationType's key) - everything else maps 1:1.
local NOTIFICATION_TYPE_TO_CATEGORY = {
    success = "success",
    error = "error",
    info = "info",
    warning = "warn",
}

addEvent(Events.NOTIFICATION_SHOW, true)
addEventHandler(Events.NOTIFICATION_SHOW, resourceRoot, function(notificationType, title, message)
    if not hud then return end
    local notifications = hud:getComponent("NotificationsComponent")
    if not notifications then return end

    local category = NOTIFICATION_TYPE_TO_CATEGORY[notificationType] or "notification"
    notifications:show(category, message or title, { title = title })
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
