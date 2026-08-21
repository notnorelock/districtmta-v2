-- Static item scheme registry - name, type, category, weight, stack
-- limit, and world-object model per item, keyed by a stable string
-- ("scheme key", stored on every items row as items.scheme_key). Loaded
-- on both sides (see meta.xml's own comment - this file is loaded twice,
-- once per side, each right after that side's own GlobalResources.lua,
-- since it reads Enums at module load time and Enums only exists once
-- the lazy-metatable proxy has run). Ported
-- from an older, unrelated project's own SCHEMES table, cut down to
-- schemes with nothing missing underneath them - only Enums.ItemType.PLAIN
-- (stackable, no special behavior) and VEHICLE_KEY (integrates with
-- gm_vehicles, already exists in this project) are here; the reference's
-- own fishing-rod USABLE-type item was NOT ported since it depended on a
-- job/fishing system this project doesn't have (see Enums.lua's own
-- ItemType comment) - add it back once that system exists, per
-- docs/Architecture.md's "Adding a new system" section.
--
-- Balance changes (weight, stack limits, new items) are a code change
-- here, not a migration - see Item.lua's own module comment on why
-- scheme data deliberately isn't a database table.
ItemSchemes = {}

--- @type table<string, ItemScheme>
-- scheme key -> {
--   type = one of Enums.ItemType,
--   category = one of Enums.ItemCategory (drives the inventory panel's
--              category tabs - Enums.ItemCategory.FOOD/KEYS/WEAPON/OTHER),
--   objectModel = number, world object model id used both for a dropped
--                 world pickup AND (client-side only) the inventory
--                 panel's item icon/preview,
--   weight = number, per-unit weight (see ItemService.lua's own carry-
--            weight check),
--   maxStack = number|false, max amount per stack - false means it never
--              stacks (e.g. a vehicle key; picking up a second one always
--              creates a separate row),
--   noDrop = boolean|nil, true if this item can never be dropped
--            (checked server-side in ItemService.lua's dropItem, not
--            just hidden client-side - never trust the panel alone),
-- }
ItemSchemes.definitions = {
    ["Mała ryba"] = {
        type = Enums.ItemType.PLAIN,
        category = Enums.ItemCategory.FOOD,
        objectModel = 2523,
        weight = 0.2,
        maxStack = 999,
    },
    ["Średnia ryba"] = {
        type = Enums.ItemType.PLAIN,
        category = Enums.ItemCategory.FOOD,
        objectModel = 2523,
        weight = 0.5,
        maxStack = 999,
    },
    ["Duża ryba"] = {
        type = Enums.ItemType.PLAIN,
        category = Enums.ItemCategory.FOOD,
        objectModel = 2523,
        weight = 0.7,
        maxStack = 999,
    },
    ["Kluczyki do pojazdu"] = {
        type = Enums.ItemType.VEHICLE_KEY,
        category = Enums.ItemCategory.KEYS,
        objectModel = 1650,
        weight = 0,
        maxStack = false,
    },
}

--- @param key string
-- @return ItemScheme|nil
ItemSchemes.get = function(key)
    return ItemSchemes.definitions[key]
end
