-- Inventory panel (I) - a plain toggle (stays open, no need to hold the
-- key), same "overlay never touches showCursor/guiSetInputEnabled by
-- design" pattern gm_scoreboard's own TAB uses, with right-click
-- independently toggling cursor/browser focus + movement lock to
-- actually interact with the panel - see ScoreboardState.lua's own
-- module comment for the full reasoning (this file follows it exactly).
InventoryState = InventoryState or {}

local inventoryOpen = false
local cursorActive = false

local function requestItems()
    triggerServerEvent(Events.INVENTORY_REQUEST_ITEMS, resourceRoot)
end

--- Only bound to onClientKey while inventoryOpen - toggles cursor/focus/
--- movement-lock on every right-click PRESS, ignores the release
--- entirely - see ScoreboardState.lua's own onRightClick for why.
local function onRightClick(key, state)
    if key ~= "mouse2" or not state then
        return
    end

    cursorActive = not cursorActive
    toggleAllControls(not cursorActive)
    exports.core_ui:uiFocusBrowser(cursorActive)
end

local function openInventory()
    if inventoryOpen then
        return
    end
    inventoryOpen = true

    exports.core_ui:uiShowOverlay("inventory")
    addEventHandler("onClientKey", root, onRightClick)
    requestItems()
end

local function closeInventory()
    if not inventoryOpen then
        return
    end
    inventoryOpen = false

    removeEventHandler("onClientKey", root, onRightClick)
    if cursorActive then
        cursorActive = false
        toggleAllControls(true)
        exports.core_ui:uiFocusBrowser(false)
    end

    exports.core_ui:uiHideOverlay("inventory")
end

local function toggleInventory()
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
        return
    end

    if inventoryOpen then
        closeInventory()
    else
        openInventory()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("i", "down", toggleInventory)
end)

addEvent(Events.INVENTORY_ITEMS_RECEIVED, true)
addEventHandler(Events.INVENTORY_ITEMS_RECEIVED, root, function(items)
    exports.core_ui:uiPushEvent(Events.PUSH_INVENTORY_ITEMS, items)
end)

-- Pushed whether or not the inventory panel itself is open - ItemToast.tsx
-- is its own always-mounted CEF overlay (like DutyIndicator/GroupInviteToast),
-- not gated behind "inventory".
addEvent(Events.ITEM_TOAST, true)
addEventHandler(Events.ITEM_TOAST, root, function(data)
    exports.core_ui:uiPushEvent(Events.PUSH_ITEM_TOAST, data)
end)

-- CEF -> client Lua (via MtaBridge.notify, relayed through core_ui's own
-- ui:notify channel - see Transport.lua's module comment - so args arrive
-- here already JSON-decoded back into their real types) - the panel's own
-- context-menu actions. Server re-validates ownership/scheme itself
-- either way (see InventoryEndpoints.lua) - this file only forwards the request.
addEvent(Events.INVENTORY_USE_ITEM, true)
addEventHandler(Events.INVENTORY_USE_ITEM, root, function(itemId)
    triggerServerEvent(Events.INVENTORY_USE_ITEM, resourceRoot, itemId)
end)

addEvent(Events.INVENTORY_DROP_ITEM, true)
addEventHandler(Events.INVENTORY_DROP_ITEM, root, function(itemId)
    triggerServerEvent(Events.INVENTORY_DROP_ITEM, resourceRoot, itemId)
end)

addEvent(Events.INVENTORY_TOGGLE_FAVORITE, true)
addEventHandler(Events.INVENTORY_TOGGLE_FAVORITE, root, function(itemId)
    triggerServerEvent(Events.INVENTORY_TOGGLE_FAVORITE, resourceRoot, itemId)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if inventoryOpen then
        closeInventory()
    end
end)
