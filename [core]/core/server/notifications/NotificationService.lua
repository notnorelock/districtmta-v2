NotificationService = NotificationService or {}

--- @param player element
-- @param notification table { type: "success"|"error"|"info"|"warning", title: string, message: string|nil }
--         Rendered by ui_hud's own native dxDraw NotificationsComponent,
--         not CEF - see Events.NOTIFICATION_SHOW's own comment.
NotificationService.send = function(player, notification)
    assert(isElement(player), "NotificationService.send expects a player element")
    assert(type(notification) == "table", "NotificationService.send expects a notification table")
    assert(type(notification.type) == "string", "notification.type is required")
    assert(type(notification.title) == "string", "notification.title is required")

    triggerClientEvent(player, Events.NOTIFICATION_SHOW, resourceRoot, notification.type, notification.title, notification.message)
end

--- Convenience broadcast variant.
-- @param notification table
NotificationService.broadcast = function(notification)
    for _, player in ipairs(getElementsByType("player")) do
        NotificationService.send(player, notification)
    end
end

function notificationServiceSend(player, notification) NotificationService.send(player, notification) end
function notificationServiceBroadcast(notification) NotificationService.broadcast(notification) end
