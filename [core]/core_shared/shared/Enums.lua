-- Common enumerations shared across resources.

Enums = {
    NotificationType = {
        SUCCESS = "success",
        ERROR = "error",
        INFO = "info",
        WARNING = "warning",
    },

    -- CEF window names only - the dxGUI admin panel/reports overlay are
    -- native windows, not CEF, and have no entry here.
    UiWindow = {
        AUTHENTICATION = "authentication",
        SPAWN_SELECT = "spawnSelect",
    },

    ReportStatus = {
        OPEN = "open",
        RESOLVED = "resolved",
    },

    PenaltyType = {
        BAN = "ban",
        MUTE = "mute",
        WARN = "warn",
        KICK = "kick",
    },

    -- gm_voice's per-player talk mode - cycled with a keybind (see
    -- gm_voice/client/VoiceModeState.lua), drives broadcast distance
    -- (VoiceService.lua) and the HUD's per-speaker indicator color.
    VoiceMode = {
        WHISPER = "whisper",
        TALK = "talk",
        SHOUT = "shout",
    },

    -- Never renumber existing values, only append new roles above BOARD.
    AccountRole = {
        PLAYER = 0,
        VETERAN = 1,
        SUPPORTER = 2,
        MODERATOR = 3,
        ADMINISTRATOR = 4,
        RCON = 5,
        BOARD = 6, -- "Zarząd"
    },

    -- gm_vehicles's Vehicle.purpose column (an "enum"-type Schema column,
    -- see Vehicle.lua) - only PRIVATE is persisted to the database today;
    -- PUBLIC vehicles are a purely scripted/runtime concept (a fixed list
    -- of spawn points in code, never written to the vehicles table - see
    -- PublicVehicles.lua). GROUP/EVENT/EXCHANGE/SHOP/RENT don't exist in
    -- this project yet (no faction/group, workshop, exchange, or shop
    -- system to back them - same reasoning as gm_blackout's medic TODO)
    -- and are deliberately NOT included here; add them only once the
    -- system they depend on actually exists, per docs/Architecture.md's
    -- "Adding a new system" section.
    VehiclePurpose = {
        PRIVATE = "private",
        PUBLIC = "public",
    },

    -- gm_items' item schemes (ItemSchemes.lua) each declare one of these -
    -- what special server-side behavior an item has beyond being a plain
    -- stackable/droppable thing. Ported from an older, unrelated
    -- project's own item "type" field (0/1/2 = plain/vehicle key/fishing
    -- rod); only PLAIN and VEHICLE_KEY exist here today - a fishing-rod-
    -- style USABLE type was deliberately NOT ported since it depended on
    -- a job/fishing system this project doesn't have, per
    -- docs/Architecture.md's "Adding a new system" section (add a type
    -- only once the system it depends on actually exists).
    ItemType = {
        PLAIN = "plain",
        VEHICLE_KEY = "vehicleKey",
    },

    -- Inventory panel category tabs (InventoryOverlay.tsx) - each
    -- ItemSchemes.lua entry declares one, "Ulubione"/"Wszystko" are
    -- derived client-side (favorite flag / no filter) rather than real
    -- categories here.
    ItemCategory = {
        FOOD = "food",
        KEYS = "keys",
        WEAPON = "weapon",
        OTHER = "other",
    },
}
