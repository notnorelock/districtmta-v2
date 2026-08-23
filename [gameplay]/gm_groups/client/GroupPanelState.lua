-- Group management panel (G) - a plain toggle (stays open, no need to
-- hold the key), right-click independently toggling cursor/browser focus
-- + movement lock to interact with it - exact same shape as
-- gm_items/client/InventoryState.lua's own module comment/pattern.
GroupPanelState = GroupPanelState or {}

local panelOpen = false
local cursorActive = false

local function requestMine()
    triggerServerEvent(Events.GROUP_REQUEST_MINE, resourceRoot)
end

--- Only bound to onClientKey while panelOpen - toggles cursor/focus/
--- movement-lock on every right-click PRESS, ignores the release
--- entirely - see InventoryState.lua's own onRightClick for why.
local function onRightClick(key, state)
    if key ~= "mouse2" or not state then
        return
    end

    cursorActive = not cursorActive
    toggleAllControls(not cursorActive)
    exports.core_ui:uiFocusBrowser(cursorActive)
end

local function openPanel()
    if panelOpen then
        return
    end
    panelOpen = true

    exports.core_ui:uiShowOverlay("groupPanel")
    addEventHandler("onClientKey", root, onRightClick)
    requestMine()
end

local function closePanel()
    if not panelOpen then
        return
    end
    panelOpen = false

    removeEventHandler("onClientKey", root, onRightClick)
    if cursorActive then
        cursorActive = false
        toggleAllControls(true)
        exports.core_ui:uiFocusBrowser(false)
    end

    exports.core_ui:uiHideOverlay("groupPanel")
end

local function togglePanel()
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
        return
    end

    if panelOpen then
        closePanel()
    else
        openPanel()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("g", "down", togglePanel)

    -- Pending invites must reach the CEF prompt even if the group panel
    -- itself is never opened this session - request them once up front,
    -- same reasoning as GROUP_INVITE_RECEIVED's own push not being gated
    -- behind panelOpen either.
    if getElementData(localPlayer, ElementData.Player.SPAWNED) == true then
        triggerServerEvent(Events.GROUP_REQUEST_INVITES, resourceRoot)
    end
end)

-- Also re-requested on every (re)spawn (native MTA event, not one of
-- this project's own custom Events.lua entries) - a player could still be
-- on the login/spawn-select screen when onClientResourceStart's own
-- request above fires, missing SPAWNED entirely.
addEventHandler("onClientPlayerSpawn", localPlayer, function()
    triggerServerEvent(Events.GROUP_REQUEST_INVITES, resourceRoot)
end)

addEvent(Events.GROUP_MINE_RECEIVED, true)
addEventHandler(Events.GROUP_MINE_RECEIVED, root, function(memberships)
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_MINE, memberships)
end)

addEvent(Events.GROUP_MEMBERS_RECEIVED, true)
addEventHandler(Events.GROUP_MEMBERS_RECEIVED, root, function(payload)
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_MEMBERS, payload)
end)

-- CEF -> client Lua (via MtaBridge.notify, relayed through core_ui's own
-- ui:notify channel), forwarded straight to the server - which
-- re-validates every permission/membership check itself (see
-- GroupEndpoints.lua's own module comment, "never trusts the panel").
addEvent(Events.GROUP_REQUEST_MEMBERS, true)
addEventHandler(Events.GROUP_REQUEST_MEMBERS, root, function(groupId)
    triggerServerEvent(Events.GROUP_REQUEST_MEMBERS, resourceRoot, { groupId = groupId })
end)

addEvent(Events.GROUP_CREATE_RANK, true)
addEventHandler(Events.GROUP_CREATE_RANK, root, function(data)
    triggerServerEvent(Events.GROUP_CREATE_RANK, resourceRoot, data)
end)

addEvent(Events.GROUP_UPDATE_RANK, true)
addEventHandler(Events.GROUP_UPDATE_RANK, root, function(data)
    triggerServerEvent(Events.GROUP_UPDATE_RANK, resourceRoot, data)
end)

addEvent(Events.GROUP_DELETE_RANK, true)
addEventHandler(Events.GROUP_DELETE_RANK, root, function(data)
    triggerServerEvent(Events.GROUP_DELETE_RANK, resourceRoot, data)
end)

addEvent(Events.GROUP_ASSIGN_MEMBER_RANK, true)
addEventHandler(Events.GROUP_ASSIGN_MEMBER_RANK, root, function(data)
    triggerServerEvent(Events.GROUP_ASSIGN_MEMBER_RANK, resourceRoot, data)
end)

addEvent(Events.GROUP_KICK_MEMBER, true)
addEventHandler(Events.GROUP_KICK_MEMBER, root, function(data)
    triggerServerEvent(Events.GROUP_KICK_MEMBER, resourceRoot, data)
end)

addEvent(Events.GROUP_LEAVE, true)
addEventHandler(Events.GROUP_LEAVE, root, function(data)
    triggerServerEvent(Events.GROUP_LEAVE, resourceRoot, data)
end)

addEvent(Events.GROUP_REQUEST_INVITABLE_PLAYERS, true)
addEventHandler(Events.GROUP_REQUEST_INVITABLE_PLAYERS, root, function(groupId)
    triggerServerEvent(Events.GROUP_REQUEST_INVITABLE_PLAYERS, resourceRoot, { groupId = groupId })
end)

addEvent(Events.GROUP_INVITABLE_PLAYERS_RECEIVED, true)
addEventHandler(Events.GROUP_INVITABLE_PLAYERS_RECEIVED, root, function(payload)
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_INVITABLE_PLAYERS, payload)
end)

addEvent(Events.GROUP_INVITE_PLAYER, true)
addEventHandler(Events.GROUP_INVITE_PLAYER, root, function(data)
    triggerServerEvent(Events.GROUP_INVITE_PLAYER, resourceRoot, data)
end)

-- Pushed to the CEF invite prompt whether or not the group panel itself
-- is open - see App.tsx's own "groupInvite" overlay, mounted
-- unconditionally alongside "groupPanel".
addEvent(Events.GROUP_INVITE_RECEIVED, true)
addEventHandler(Events.GROUP_INVITE_RECEIVED, root, function(payload)
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_INVITE_RECEIVED, payload)
end)

addEvent(Events.GROUP_INVITES_RECEIVED, true)
addEventHandler(Events.GROUP_INVITES_RECEIVED, root, function(invites)
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_INVITES, invites)
end)

addEvent(Events.GROUP_ACCEPT_INVITE, true)
addEventHandler(Events.GROUP_ACCEPT_INVITE, root, function(inviteId)
    triggerServerEvent(Events.GROUP_ACCEPT_INVITE, resourceRoot, { inviteId = inviteId })
end)

addEvent(Events.GROUP_DECLINE_INVITE, true)
addEventHandler(Events.GROUP_DECLINE_INVITE, root, function(inviteId)
    triggerServerEvent(Events.GROUP_DECLINE_INVITE, resourceRoot, { inviteId = inviteId })
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if panelOpen then
        closePanel()
    end
end)
