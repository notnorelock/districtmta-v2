WeatherRegions = WeatherRegions or {}

WeatherRegions.REGIONS = {
    {
        id = "losSantos",
        cities = { "Los Santos", "San Fierro", "Red County", "Flint County" },
        pool = {
            { icon = "sunny", labelKey = "sunny", weathers = { 0, 1, 11 }, chance = 50 },
            { icon = "rain", labelKey = "rain", weathers = { 8, 16 }, chance = 2 },
            { icon = "partialyCloudy", labelKey = "partialyCloudy", weathers = { 4, 3 }, chance = 35 },
        },
    },
    {
        id = "whetstone",
        cities = { "Whetstone" },
        pool = {
            { icon = "snow", labelKey = "snow", weathers = { 9 }, chance = 50 },
            { icon = "sunny", labelKey = "sunny", weathers = { 0 }, chance = 50 },
        },
    },
    {
        id = "lasVenturas",
        cities = { "Las Venturas", "Bone County", "Tierra Robada" },
        pool = {
            { icon = "sunny", labelKey = "sunny", weathers = { 0, 1 }, chance = 100 },
        },
    },
}

local CITY_TO_REGION = {}
for _, region in ipairs(WeatherRegions.REGIONS) do
    for _, city in ipairs(region.cities) do
        CITY_TO_REGION[city] = region
    end
end

function WeatherRegions.regionAt(x, y, z)
    local cityName = getZoneName(x, y, z, true)
    return CITY_TO_REGION[cityName], cityName
end
