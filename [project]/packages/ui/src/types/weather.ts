/** One of gm_weather/server/WeatherRegions.lua's REGIONS entries' `icon` value. */
export type WeatherIcon = "sunny" | "rain" | "partialyCloudy" | "snow";

/** Mirrors the payload shape gm_weather/server/WeatherService.lua's toPayload builds. */
export interface WeatherData {
  region: string;
  city: string;
  weatherId: number;
  icon: WeatherIcon;
  labelKey: string;
}
