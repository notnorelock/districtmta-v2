NotificationService = NotificationService or {}

--- @param player element
-- @param notification table { type: "success"|"error"|"info"|"warning", title: string, message: string|nil }
--         Rendered by ui_hud's own native dxDraw NotificationsComponent -
--         ui_hud owns the toast/transport itself (NotificationBridge.lua),
--         this just calls its export rather than reaching across with a
--         raw triggerClientEvent of its own.
NotificationService.send = function(player, notification)
    assert(isElement(player), "NotificationService.send expects a player element")
    assert(type(notification) == "table", "NotificationService.send expects a notification table")
    assert(type(notification.type) == "string", "notification.type is required")
    assert(type(notification.title) == "string", "notification.title is required")

    pcall(function()
        exports.ui_hud:notificationBridgeShow(player, notification.type, notification.title, notification.message)
    end)
end

--- Convenience broadcast variant.
-- @param notification table
NotificationService.broadcast = function(notification)
    assert(type(notification) == "table", "NotificationService.broadcast expects a notification table")
    assert(type(notification.type) == "string", "notification.type is required")
    assert(type(notification.title) == "string", "notification.title is required")

    pcall(function()
        exports.ui_hud:notificationBridgeBroadcast(notification.type, notification.title, notification.message)
    end)
end

function notificationServiceSend(player, notification) NotificationService.send(player, notification) end
function notificationServiceBroadcast(notification) NotificationService.broadcast(notification) end
