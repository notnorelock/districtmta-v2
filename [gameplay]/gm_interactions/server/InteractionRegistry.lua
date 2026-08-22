-- Registry of world interactions - ported from an older, unrelated
-- project's reference implementation (pd_interactions), cut down to what
-- this project actually has. The original registry mixed a generic
-- interaction FRAMEWORK (element type, permission/rank/condition gates,
-- client/server handler) with dozens of concrete interactions tied to
-- systems that don't exist here yet (faction/group duty, SAPD/SAMD/SAFD
-- roles, stretchers, tuning workshops, vehicle exchange, casino) - only
-- the framework itself and the admin vehicle interactions (fix/flip/move
-- to self) were ported, since those are the only ones with nothing
-- missing underneath them. Everything else is deliberately NOT here yet -
-- add an entry once the system it depends on actually exists, per
-- docs/Architecture.md's "Adding a new system" section, the same
-- convention Enums.VehiclePurpose's own comment follows for GROUP/EVENT/etc.
InteractionRegistry = InteractionRegistry or {}

--- @type table<string, InteractionDefinition>
-- key -> {
--   label = string,
--   icon = string ("IconXxx" name from @tabler/icons-solidjs, matched
--          client-side - see WorldInteractionOverlay.tsx's own ICON map),
--   elementType = "player"|"vehicle"|"object",
--   permissionBit = number|nil (one of Permissions.Bit.*, checked via
--                   exports.core:permissionsHasRole against the caller's
--                   role - absent means "no permission gate, only the
--                   generic range/type checks apply"),
--   condition = function(player, element): boolean|nil (extra per-call
--               gate beyond permissionBit, e.g. "is this vehicle actually
--               flipped"),
--   handler = function(player, element) (the actual effect - always
--             server-side; this project has no client-only interaction
--             handler today, unlike the reference's client= field, since
--             nothing ported so far needs one),
-- }
InteractionRegistry.definitions = {}

--- Registers one interaction definition under `key`. Called at load time
--- by this file itself - a separate registration step (rather than one
--- big literal table) so future systems (a group/faction resource, say)
--- can register their own entries from their own resource without
--- editing this file, the same "extend, don't modify core" shape
--- Architecture.md asks for elsewhere.
-- @param key string unique interaction id, "namespace:action" convention
--        (see the entries below)
-- @param definition InteractionDefinition
InteractionRegistry.register = function(key, definition)
    InteractionRegistry.definitions[key] = definition
end

--- @param key string
-- @return InteractionDefinition|nil
InteractionRegistry.get = function(key)
    return InteractionRegistry.definitions[key]
end

--- @param player element
-- @param key string
-- @param element element the interaction's target
-- @return boolean
InteractionRegistry.isAllowed = function(player, key, element)
    local definition = InteractionRegistry.definitions[key]
    if not definition then
        return false
    end

    if definition.elementType and getElementType(element) ~= definition.elementType then
        return false
    end

    if definition.permissionBit then
        local role = PlayerService.getRole(player)
        if not role or not Permissions.has(role, definition.permissionBit) then
            return false
        end
    end

    if definition.condition and not definition.condition(player, element) then
        return false
    end

    return true
end

--- @param player element
-- @param element element
-- @return string[] keys of every interaction currently allowed on `element` for `player`
InteractionRegistry.availableFor = function(player, element)
    local keys = {}
    for key in pairs(InteractionRegistry.definitions) do
        if InteractionRegistry.isAllowed(player, key, element) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        return InteractionRegistry.definitions[a].label < InteractionRegistry.definitions[b].label
    end)
    return keys
end

-- Admin vehicle interactions - gated on PlayerService.isOnDuty (currently
-- on-duty staff only), not permissionBit/Permissions.Bit.VEHICLE_ADMIN -
-- a permission bit only says a role is ALLOWED to go on duty, not that
-- the player actually has right now (an off-duty admin shouldn't see
-- these in the interaction menu at all, same as they don't get the admin
-- GUI). Effects touch the live vehicle element directly via plain MTA
-- natives (setElementHealth, setElementRotation, ...) rather than going
-- through gm_vehicles at all - gm_vehicles' own periodic autosave/
-- onVehicleExit save picks up the resulting state on its own, no
-- cross-resource call needed (see docs/Architecture.md's "the one hard
-- rule" - this deliberately avoids needing one).
InteractionRegistry.register("vehicle:adminFix", {
    label = "Napraw pojazd",
    icon = "IconTool",
    elementType = "vehicle",
    condition = function(player)
        return PlayerService.isOnDuty(player) == true
    end,
    handler = function(player, vehicle)
        fixVehicle(vehicle)
        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Naprawiono pojazd." })
        Logger.info("InteractionRegistry", "Admin fixed a vehicle", {
            player = getPlayerName(player),
            vehicleId = getElementData(vehicle, ElementData.Vehicle.ID),
        })
    end,
})

InteractionRegistry.register("vehicle:adminFlip", {
    label = "Obróć pojazd",
    icon = "IconRotate",
    elementType = "vehicle",
    condition = function(player, vehicle)
        if not PlayerService.isOnDuty(player) then
            return false
        end
        local rx = getElementRotation(vehicle)
        return rx > 60 and rx < 250
    end,
    handler = function(player, vehicle)
        local rx, ry, rz = getElementRotation(vehicle)
        local x, y, z = getElementPosition(vehicle)
        setElementRotation(vehicle, rx + 180, ry, rz)
        setElementPosition(vehicle, x, y, z + 1.5)
        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Obrócono pojazd." })
        Logger.info("InteractionRegistry", "Admin flipped a vehicle", {
            player = getPlayerName(player),
            vehicleId = getElementData(vehicle, ElementData.Vehicle.ID),
        })
    end,
})

-- World item pickup - gm_items (a separate resource) can't register its
-- own handler here directly, since a handler is a Lua function value and
-- this project's hard rule (see docs/Architecture.md) says a callback
-- can never cross a resource boundary. Instead this entry is generic:
-- the condition only checks for ElementData.Item.ID's PRESENCE (no
-- knowledge of gm_items' own item shape/schemes needed), and the handler
-- only forwards a plain triggerEvent to gm_items - the actual pickup
-- logic (ownership, weight check, row deletion) lives entirely in
-- gm_items/server/ItemService.lua's own Events.ITEM_PICKUP listener.
InteractionRegistry.register("object:itemPickup", {
    label = "Podnieś",
    icon = "IconHandGrab",
    elementType = "object",
    condition = function(_, object)
        return getElementData(object, ElementData.Item.ID) ~= false
    end,
    handler = function(player, object)
        triggerEvent(Events.ITEM_PICKUP, resourceRoot, player, getElementData(object, ElementData.Item.ID))
    end,
})

-- Shared by every vehicle:* interaction below that's gated on actually
-- carrying that vehicle's key (lock, hood, trunk) - itemServiceHasVehicleKey
-- is a read-only query export (plain data in/out, safe across the
-- resource boundary per docs/Architecture.md's "the one hard rule"),
-- pcall'd since gm_items could in principle be stopped/restarting
-- independently of gm_interactions.
-- @param player element
-- @param vehicle vehicle
-- @return boolean
local function hasVehicleKey(player, vehicle)
    local vehicleId = getElementData(vehicle, ElementData.Vehicle.ID)
    if not vehicleId then
        return false
    end
    local ok, hasKey = pcall(function()
        return exports.gm_items:itemServiceHasVehicleKey(player, vehicleId)
    end)
    return ok and hasKey == true
end

-- Lock/unlock toggle, gated on carrying that specific vehicle's key -
-- same effect as ItemUseHandlers.lua's own VEHICLE_KEY "use" handler, just
-- reachable from the world interaction menu directly instead of opening
-- the inventory panel to click "Użyj". Goes through gm_vehicles'
-- toggleVehicleLock export (plain data in/out, safe across the resource
-- boundary per docs/Architecture.md's "the one hard rule") rather than
-- calling setVehicleLocked directly, so the headlight-flash signal
-- (VehicleLockService.lua) fires from this too, not just gm_vehicles' own
-- callers. Pcall'd since gm_vehicles could in principle be stopped/
-- restarting independently of gm_interactions.
InteractionRegistry.register("vehicle:toggleLock", {
    label = "Otwórz/zamknij pojazd",
    icon = "IconLock",
    elementType = "vehicle",
    condition = hasVehicleKey,
    handler = function(player, vehicle)
        pcall(function()
            exports.gm_vehicles:toggleVehicleLock(vehicle)
        end)
    end,
})

-- Door index 0 (hood) / 1 (trunk) - see
-- https://wiki.multitheftauto.com/wiki/GetVehicleDoorState /
-- SetVehicleDoorOpenRatio. setVehicleDoorState snaps straight to the
-- target state with no animation - setVehicleDoorOpenRatio(vehicle, door,
-- ratio, time) eases between the door's current and target ratio over
-- `time` ms instead, the same smooth swing a player gets from actually
-- opening a door by walking into it. Touches the vehicle element directly
-- rather than through gm_vehicles - a couple of native calls, not worth
-- adding an export for (same reasoning the admin vehicle interactions
-- above already give for touching the vehicle element directly).
local DOOR_ANIMATION_MS = 400

InteractionRegistry.register("vehicle:toggleHood", {
    label = "Otwórz/zamknij maskę",
    icon = "IconEngine",
    elementType = "vehicle",
    condition = hasVehicleKey,
    handler = function(_, vehicle)
        local isOpen = getVehicleDoorOpenRatio(vehicle, 0) > 0
        setVehicleDoorOpenRatio(vehicle, 0, isOpen and 0 or 1, DOOR_ANIMATION_MS)
    end,
})

InteractionRegistry.register("vehicle:toggleTrunk", {
    label = "Otwórz/zamknij bagażnik",
    icon = "IconBox",
    elementType = "vehicle",
    condition = hasVehicleKey,
    handler = function(_, vehicle)
        local isOpen = getVehicleDoorOpenRatio(vehicle, 1) > 0
        setVehicleDoorOpenRatio(vehicle, 1, isOpen and 0 or 1, DOOR_ANIMATION_MS)
    end,
})

InteractionRegistry.register("vehicle:adminMoveToSelf", {
    label = "Przenieś pojazd do siebie",
    icon = "IconArrowBackUp",
    elementType = "vehicle",
    condition = function(player)
        return PlayerService.isOnDuty(player) == true
    end,
    handler = function(player, vehicle)
        local x, y, z = getElementPosition(player)
        local rx, ry, rz = getElementRotation(player)
        local rad = math.rad(rz)
        setElementPosition(vehicle, x + math.sin(-rad) * 1.5, y + math.cos(-rad) * 1.5, z)
        setElementRotation(vehicle, rx, ry, rz)
        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Przeniesiono pojazd do siebie." })
        Logger.info("InteractionRegistry", "Admin moved a vehicle to self", {
            player = getPlayerName(player),
            vehicleId = getElementData(vehicle, ElementData.Vehicle.ID),
        })
    end,
})
