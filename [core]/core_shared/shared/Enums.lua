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
}
