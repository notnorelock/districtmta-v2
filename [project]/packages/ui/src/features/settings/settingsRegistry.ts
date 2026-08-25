/**
 * CEF-side parallel to gm_settings/server/SettingsRegistry.lua - the
 * label list for every toggle this project actually has an
 * implementation for. NOT shared/codegen'd with the Lua registry (same
 * "independently typed on each side" convention every other push
 * payload in this project already follows).
 *
 * Adding toggle #2 later: one entry here (id + labelKey) plus one entry
 * in SettingsRegistry.lua (id + defaultEnabled) plus one EFFECTS branch
 * in SettingsState.lua - SettingsPanelOverlay.tsx itself needs no
 * changes, it renders this array generically.
 */
export interface SettingToggleDefinition {
  id: string;
  labelKey: string;
}

export const SETTINGS_REGISTRY: SettingToggleDefinition[] = [{ id: "hud_disabled", labelKey: "settings.toggle.hudDisabled" }];
