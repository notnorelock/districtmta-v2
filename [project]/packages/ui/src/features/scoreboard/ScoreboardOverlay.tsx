import { type Component, For, Show, createMemo, createSignal } from "solid-js";
import { Users, Wifi, X } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { Badge } from "@/components/ui/Badge";
import { TextField, TextFieldInput } from "@/components/ui/TextField";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/Tooltip";
import { scoreboardStore } from "@/stores/scoreboard.store";
import { AccountRole } from "@/types/account";
import type { ScoreboardPlayer } from "@/types/scoreboard";
import { ScoreboardStatus } from "@/types/scoreboard";
import { t } from "@/i18n";
import styles from "./ScoreboardOverlay.module.scss";

/** Mirrors Permissions.colorForRole in core/server/accounts/Permissions.lua - keep in sync manually, same convention as types/account.ts's AccountRole mirror. Not shown for PLAYER (the default rank, not worth calling out next to every ordinary player's status). */
const ROLE_LABEL: Partial<Record<AccountRole, string>> = {
  [AccountRole.VETERAN]: "Weteran",
  [AccountRole.SUPPORTER]: "Pomocnik",
  [AccountRole.MODERATOR]: "Moderator",
  [AccountRole.ADMINISTRATOR]: "Administrator",
  [AccountRole.RCON]: "RCON",
  [AccountRole.BOARD]: "Zarząd",
};

const STATUS_LABEL_KEY: Record<ScoreboardPlayer["status"], string> = {
  [ScoreboardStatus.DOWNLOADING]: "scoreboard.status.downloading",
  [ScoreboardStatus.AUTHENTICATING]: "scoreboard.status.authenticating",
  [ScoreboardStatus.SELECTING_SPAWN]: "scoreboard.status.selectingSpawn",
  [ScoreboardStatus.IN_GAME]: "scoreboard.status.inGame",
};

const STATUS_DOT_VARIANT: Record<ScoreboardPlayer["status"], "warning" | "success"> = {
  [ScoreboardStatus.DOWNLOADING]: "warning",
  [ScoreboardStatus.AUTHENTICATING]: "warning",
  [ScoreboardStatus.SELECTING_SPAWN]: "warning",
  [ScoreboardStatus.IN_GAME]: "success",
};

function pingClass(ping: number): string {
  if (ping >= 150) return styles.pingBad as string;
  if (ping >= 80) return styles.pingOk as string;
  return styles.pingGood as string;
}

function initialOf(name: string): string {
  return name.replace(/#[0-9A-Fa-f]{6}/g, "").trim().charAt(0).toUpperCase() || "?";
}

/**
 * TAB scoreboard - connected-player list as a plain overlay (see
 * gm_scoreboard/client/ScoreboardState.lua's own comment: TAB toggles it
 * open/closed - it stays open, no need to hold the key - without
 * touching cursor/controls at all; right-click independently toggles
 * cursor focus and movement lock to interact with the list/search box
 * below, also a press-to-toggle rather than hold). Rendered
 * unconditionally (see App.tsx) using its own "scoreboard" overlay key,
 * same pattern as BlackoutOverlay/HudBar.
 *
 * The account ROLE (staff rank - moderator/admin/etc.) is shown in
 * parentheses next to the in-game STATUS ("W grze (Zarząd)"), not as its
 * own column - it's a meta detail about the player's account, not their
 * in-game group/faction (the separate badge on the right, e.g. SAPD/SAMC -
 * a placeholder today, see below), and the two must not read as the same
 * kind of thing. The role is only ever populated while genuinely ON DUTY
 * (see ScoreboardService.lua's isOnDuty) - a high account role alone does
 * not show here, same as this project's nametag-color logic already works.
 *
 * login/role/faction are null for a player who hasn't authenticated yet
 * (see ScoreboardService.lua's toEntry) - shown as the raw connection name
 * and a placeholder rather than hidden, so a still-downloading/logging-in
 * player is still visible in the list (that's the point of the status
 * column), just without account-derived columns filled in yet.
 *
 * Layout follows a reference screenshot the user provided (a finished
 * scoreboard from elsewhere) for structure/style only - the avatar image,
 * friends list, and level system visible in that reference don't exist in
 * this project and are deliberately NOT implemented: the avatar is a
 * plain initial-letter placeholder, and there is no middle "friends"
 * column, only the existing role/faction data this project actually has.
 * The header's logo is a text placeholder until a real asset is provided.
 */
export const ScoreboardOverlay: Component = () => {
  const [search, setSearch] = createSignal("");

  const filteredPlayers = createMemo(() => {
    const needle = search().trim().toLowerCase();
    const all = scoreboardStore.players();
    if (!needle) return all;

    return all.filter((player) => {
      const haystack = `${player.name} ${player.login ?? ""} ${player.id}`.toLowerCase();
      return haystack.includes(needle);
    });
  });

  const statusText = (player: ScoreboardPlayer) => {
    const status = t()(STATUS_LABEL_KEY[player.status]);
    const roleLabel = player.role !== null ? ROLE_LABEL[player.role] : undefined;
    // "Zarząd" (admin duty) and "Służba <grupa>" (group duty) share ONE
    // parenthetical, comma-separated, in that order - "W grze (Zarząd,
    // Służba SAPD)" for an admin on group duty, "W grze (Służba SAPD)"
    // for a non-admin one, "W grze (Zarząd)"/"W grze" unchanged when the
    // other is absent. `faction` doubles as the group-duty name here (see
    // ScoreboardService.lua's own groupDutyNameOf) - the separate badge
    // further down the row still renders it too, this is purely the
    // status-line composition the user specifically asked for.
    const parts = [roleLabel, player.faction ? `${t()("scoreboard.status.onGroupDuty")} ${player.faction}` : undefined].filter(Boolean);
    return parts.length > 0 ? `${status} (${parts.join(", ")})` : status;
  };

  return (
    <Overlay name="scoreboard" transitionName="scoreboard">
      <div class={styles.root}>
        <div class={styles.panel}>
          <div class={styles.header}>
            <div class={styles.logo}>
              <span class={styles.logoAccent}>district</span>
              <span>MTA</span>
            </div>

            <TextField class={styles.search} value={search()} onChange={setSearch}>
              <div class={styles.searchInputWrap}>
                {/* type="text", not "search" - Chromium/CEF's native
                    search-input clear-X doesn't match this project's
                    styling, so this uses a plain text input plus an
                    explicit lucide X button instead, shown only once
                    there's something to clear. */}
                <TextFieldInput type="text" class={styles.searchInput} placeholder={t()("scoreboard.searchPlaceholder")} />
                <Show when={search().length > 0}>
                  <button type="button" class={styles.searchClear} onClick={() => setSearch("")} aria-label={t()("scoreboard.searchClear")}>
                    <X size={14} />
                  </button>
                </Show>
              </div>
            </TextField>

            <Tooltip placement="bottom">
              <TooltipTrigger as="div" class={styles.count}>
                <span>{scoreboardStore.players().length}</span>
                <Users size={16} />
              </TooltipTrigger>
              <TooltipContent>{t()("scoreboard.count.tooltip")}</TooltipContent>
            </Tooltip>
          </div>

          <div class={styles.listWrap}>
            <For
              each={filteredPlayers()}
              fallback={<div class={styles.empty}>{t()("scoreboard.empty")}</div>}
            >
              {(player) => (
                <div class={styles.row}>
                  <div class={styles.avatar}>{initialOf(player.name)}</div>

                  <div class={styles.identity}>
                    <span class={styles.playerName}>
                      <span class={styles.playerId}>({player.id})</span>{" "}
                      <span style={player.nameColor ? { color: player.nameColor } : undefined}>{player.login ?? player.name}</span>
                    </span>
                    <span class={styles.playerStatus}>
                      <Badge variant={STATUS_DOT_VARIANT[player.status]} size="dot" />
                      {statusText(player)}
                    </span>
                  </div>

                  <Show when={player.faction}>
                    <Badge variant="muted">{player.faction}</Badge>
                  </Show>

                  <Tooltip placement="left">
                    <TooltipTrigger as="div" class={styles.pingCol}>
                      <span>{player.ping}</span>
                      <Wifi size={14} class={pingClass(player.ping)} />
                    </TooltipTrigger>
                    <TooltipContent>{t()("scoreboard.ping.tooltip")}</TooltipContent>
                  </Tooltip>
                </div>
              )}
            </For>
          </div>

          <div class={styles.footer}>{t()("scoreboard.hint")}</div>
        </div>
      </div>
    </Overlay>
  );
};
