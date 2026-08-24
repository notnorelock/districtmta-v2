-- Canonical element data key registry - every setElementData/
-- getElementData/removeElementData key used across resources should be
-- read from here instead of typed as a raw string literal at the call
-- site, same reasoning as Events.lua's event name registry.

ElementData = {
    Player = {
        LOGGED = "player:logged",
        SPAWNED = "player:spawned",
        ADMIN = "player:admin",
        ID = "player:id",
        SKIN = "player:skin",
        SESSION_KEY = "player:sessionKey",
        -- Set true once Events.LOADING_READY has fired for this player
        -- (core_bootstrap's chain finished AND their CEF frontend reported
        -- ready - see core_loading/server/LoadingGate.lua). Absent/false
        -- means "still downloading resources", the one loading stage
        -- LoadingGate itself never exposed anywhere else - added for
        -- gm_scoreboard to tell "downloading" apart from "authenticating".
        LOADING_READY = "player:loadingReady",
        VOICE = "player:voice",
        VOICE_START = "player:voiceStart",
        VOICE_MODE = "player:voiceMode",
        -- Absolute os.time() (seconds) the player's current blackout
        -- ends, or absent entirely while not blacked out - "key absent"
        -- is the presence check (getElementData returns false for an
        -- absent key), same convention as ElementData.Player.ADMIN. An
        -- absolute end time, not a remaining-duration counter, survives
        -- a gm_blackout restart without drifting - any reader computes
        -- (BLACKOUT_UNTIL - os.time()) itself, on demand.
        BLACKOUT_UNTIL = "player:blackoutUntil",

        -- total seconds this blackout was started with (BlackoutService.
        -- start's durationSeconds, defaulting to BLACKOUT_DURATION_S) -
        -- needed alongside BLACKOUT_UNTIL so a gm_blackout restart can
        -- re-derive the CEF countdown ring's progress normalization, not
        -- just the raw seconds remaining.
        BLACKOUT_DURATION = "player:blackoutDuration",

        -- Reserved ahead of an actual AFK-detection system (none exists
        -- in this project yet) - gm_nametags/client/NametagState.lua
        -- already reads this key for its AFK status icon (absent/false =
        -- not AFK, same "getElementData returns false for an unset key"
        -- convention as ADMIN), so whatever future system sets it doesn't
        -- need to also touch the nametag code.
        AFK = "player:afk",

        -- Holds a table ({ group = { id, name, type }, rank = { id, name } })
        -- or is absent while not on group duty - same presence-check
        -- convention as ADMIN above (`type(...) == "table"`, never `~= nil` -
        -- getElementData returns false, not real nil, for an unset key).
        -- Set/cleared by gm_groups/server/GroupDutyService.lua's own
        -- enterDuty/exitDuty (a SEPARATE resource from core, same as
        -- BLACKOUT_UNTIL is set by gm_blackout - MTA's setElementData/
        -- getElementData work across the resource boundary on any
        -- element regardless of which resource created it, no export
        -- needed). Exists so gm_scoreboard can read a player's group duty
        -- status directly, the same zero-dependency way it already reads
        -- ADMIN, instead of needing a cross-resource call into gm_groups.
        GROUP_DUTY = "player:groupDuty",

        -- Holds an array of granted license category strings (e.g.
        -- {"A","B"}, Enums.LicenseCategory values) the player currently
        -- holds AND is not suspended from, or is absent entirely if none
        -- granted - same presence-check convention as GROUP_DUTY above
        -- (type(x) == "table", never ~= nil). A category can be granted
        -- but currently suspended - suspended categories are OMITTED
        -- from this array while the suspension is active
        -- (gm_licenses/server/LicenseExamService.lua's resyncElementData
        -- re-syncs this on login/grant/suspend/unsuspend), so any other
        -- resource reading this key directly (e.g. a future
        -- gm_vehicles_interaction "needs license to drive" gate) never
        -- needs to know suspension exists as its own concept - "in this
        -- array" already means "currently allowed to drive this category".
        LICENSES = "player:licenses",
    },
    Account = {
        PREMIUM = "account:premium",
        MUTE = "account:mute",
    },
    Vehicle = {
        -- { name: string, url: string } or nil for "off" - mirrored onto
        -- the vehicle itself (not just pushed to occupants) so a player
        -- entering an already-playing vehicle mid-song can be caught up
        -- via a synchronous read instead of waiting on the next change.
        RADIO_STATION = "vehicle:radioStation",

        -- gm_vehicles: the vehicles table row this world vehicle element
        -- was spawned from - absent for a vehicle gm_vehicles didn't
        -- create (e.g. gm_roleplay's /veh temporary spawns).
        ID = "vehicle:id",
        -- One of Enums.VehiclePurpose's values.
        PURPOSE = "vehicle:purpose",
        -- accounts.id of this vehicle's owner (the CREATING admin for a
        -- GROUP-purpose vehicle - audit trail only, not the access gate).
        OWNER_ACCOUNT_ID = "vehicle:ownerAccountId",
        -- groups.id this vehicle belongs to - absent for a PRIVATE/PUBLIC
        -- vehicle. See gm_groups' groupServiceCanUseVehicle export for the
        -- actual access decision (membership + rank allowlist + duty-if-fraction).
        GROUP_ID = "vehicle:groupId",
        -- Round-trip cache for the "upgrades" JSON column's non-parts
        -- fields (neons/paintjob/engine) between load and save - no
        -- in-game system reads/writes these yet (no tuning workshop),
        -- kept here only so VehicleService.save doesn't silently drop
        -- them on the next save. See VehicleService.lua's own comment.
        UPGRADES_CACHE = "vehicle:upgradesCache",
        -- Round-trip cache for "last_drivers" between load and save -
        -- same reasoning as UPGRADES_CACHE above.
        LAST_DRIVERS_CACHE = "vehicle:lastDriversCache",
        -- gm_licenses: true on a temporary practical-exam vehicle
        -- (LicenseExamService.lua's own createVehicle call) - exam
        -- vehicles are how a player WITHOUT a license learns to drive
        -- one, so gm_vehicles_interaction's own license-category gate
        -- (onVehicleStartEnter) must skip them rather than locking the
        -- examinee out of their own exam.
        EXAM_VEHICLE = "vehicle:examVehicle",
    },
    -- gm_items: a world-dropped item's own "object" element (not the
    -- world root element gm_interactions targets) mirrors these - see
    -- ItemService.lua's spawnWorldItem.
    Item = {
        -- items table row id this world object was spawned from.
        ID = "item:id",
        -- ItemSchemes.lua key (a string name, e.g. "Mała ryba") - read by
        -- the pickup interaction handler to know what it's picking up
        -- without a round-trip to the database first.
        SCHEME_KEY = "item:schemeKey",
    },
}

-- AuthUiController.lua mirrors most of an account row's own columns onto
-- "account:<field>" element data dynamically (id, role, created_at, ...)
-- rather than one constant per column - this builds that key consistently
-- instead of every call site formatting the string by hand.
-- @param field string account column name, e.g. "id" or "role"
-- @return string
ElementData.accountField = function(field)
    return "account:" .. field
end
