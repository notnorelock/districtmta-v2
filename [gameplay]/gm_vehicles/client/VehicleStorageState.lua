-- Vehicle storage panel - unlike inventory/scoreboard (player-toggled via
-- a keybind), this overlay is server-driven: walking into a lot's enter
-- marker opens it (Events.VEHICLE_STORAGE_OPEN), walking out closes it
-- (VEHICLE_STORAGE_CLOSE) - see VehicleStorageService.lua's own
-- onMarkerHit/onMarkerLeave. Right-click focus toggle follows the exact
-- same pattern ScoreboardState.lua/InventoryState.lua already use.
-- Storing a vehicle has no client-side involvement at all - driving onto
-- the lot's SEPARATE store_position zone stores it automatically, server-
-- side, the instant it enters (see VehicleStorageService.lua's
-- onStoreZoneHit/tryStoreVehicle) - no keypress, no panel interaction.
VehicleStorageState = VehicleStorageState or {}

local storageOpen = false
local cursorActive = false
local currentStoreId = nil

local function onRightClick(key, state)
    if key ~= "mouse2" or not state then
        return
    end

    cursorActive = not cursorActive
    toggleAllControls(not cursorActive)
    exports.core_ui:uiFocusBrowser(cursorActive)
end

local function openStorage(storeId, storeName)
    currentStoreId = storeId
    if not storageOpen then
        storageOpen = true
        addEventHandler("onClientKey", root, onRightClick)
    end

    exports.core_ui:uiPushEvent(Events.PUSH_VEHICLE_STORAGE_ITEMS, { storeId = storeId, storeName = storeName, vehicles = {} })
    exports.core_ui:uiShowOverlay("vehicleStorage")
end

local function closeStorage()
    if not storageOpen then
        return
    end
    storageOpen = false
    currentStoreId = nil

    removeEventHandler("onClientKey", root, onRightClick)
    if cursorActive then
        cursorActive = false
        toggleAllControls(true)
        exports.core_ui:uiFocusBrowser(false)
    end

    exports.core_ui:uiHideOverlay("vehicleStorage")
end

addEvent(Events.VEHICLE_STORAGE_OPEN, true)
addEventHandler(Events.VEHICLE_STORAGE_OPEN, root, openStorage)

addEvent(Events.VEHICLE_STORAGE_CLOSE, true)
addEventHandler(Events.VEHICLE_STORAGE_CLOSE, root, closeStorage)

addEvent(Events.VEHICLE_STORAGE_ITEMS_RECEIVED, true)
addEventHandler(Events.VEHICLE_STORAGE_ITEMS_RECEIVED, root, function(storeId, vehicles)
    if storeId ~= currentStoreId then
        return
    end
    exports.core_ui:uiPushEvent(Events.PUSH_VEHICLE_STORAGE_ITEMS, { storeId = storeId, vehicles = vehicles })
end)

-- CEF -> client Lua (via MtaBridge.notify, relayed through core_ui's own
-- ui:notify channel - see gm_items/client/InventoryState.lua's identical
-- pattern/comment) - the panel's own "odbierz" button. Server re-validates
-- ownership/store membership itself either way (see
-- VehicleStorageService.lua) - this file only forwards the request.
addEvent(Events.VEHICLE_STORAGE_RETRIEVE, true)
addEventHandler(Events.VEHICLE_STORAGE_RETRIEVE, root, function(vehicleId)
    triggerServerEvent(Events.VEHICLE_STORAGE_RETRIEVE, resourceRoot, vehicleId)
end)

addEventHandler("onClientResourceStop", resourceRoot, closeStorage)
