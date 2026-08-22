-- Server-side entry point into this resource's own native dxDraw toast
-- stack (client/Components/NotificationsComponent.lua) - owns
-- Events.NOTIFICATION_SHOW itself (fires it directly at the target
-- player(s)) so any other resource wanting to show a toast just calls
-- this export instead of knowing the event/transport at all. core's own
-- NotificationService.send/broadcast (core/server/notifications/
-- NotificationService.lua) is the main caller, going through this export
-- rather than triggering the event itself - same reasoning as every other
-- cross-resource entry point in this project (e.g. gm_items's
-- itemServiceHasVehicleKey): the resource that owns the behavior owns the
-- export, callers never reach across with a raw triggerClientEvent of
-- their own.
NotificationBridge = NotificationBridge or {}

--- @param player element
-- @param notificationType string "success"|"error"|"info"|"warning"
-- @param title string|nil omit to use NotificationsComponent.lua's own
--        per-category default heading ("Sukces"/"Błąd"/...)
-- @param message string|nil
NotificationBridge.show = function(player, notificationType, title, message)
    assert(isElement(player), "NotificationBridge.show expects a player element")
    assert(type(notificationType) == "string", "notificationType is required")
    assert(title == nil or type(title) == "string", "title must be a string if given")

    triggerClientEvent(player, Events.NOTIFICATION_SHOW, resourceRoot, notificationType, title, message)
end

--- @param notificationType string "success"|"error"|"info"|"warning"
-- @param title string|nil
-- @param message string|nil
NotificationBridge.broadcast = function(notificationType, title, message)
    for _, player in ipairs(getElementsByType("player")) do
        NotificationBridge.show(player, notificationType, title, message)
    end
end

function notificationBridgeShow(player, notificationType, title, message)
    NotificationBridge.show(player, notificationType, title, message)
end

function notificationBridgeBroadcast(notificationType, title, message)
    NotificationBridge.broadcast(notificationType, title, message)
end
