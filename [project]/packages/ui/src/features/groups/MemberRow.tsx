import { type Component, For, Show } from "solid-js";
import { UserX } from "lucide-solid";
import { t } from "@/i18n";
import type { GroupMember, GroupRank } from "@/types/group";
import styles from "./GroupPanelOverlay.module.scss";

interface MemberRowProps {
  member: GroupMember;
  ranks: GroupRank[];
  isSelf: boolean;
  /** True if this member currently holds a rank with is_leader - can never be kicked, see GroupEndpoints.lua's own GROUP_KICK_MEMBER handler. */
  isLeaderRow: boolean;
  canManage: boolean;
  onAssignRank: (rankId: number) => void;
  onKick: () => void;
}

/**
 * One roster row - name (offline members show a placeholder, see
 * GroupEndpoints.lua's own onlinePlayerNameForAccount comment), a rank
 * dropdown when the viewer has manage_members (plain text otherwise), and
 * a kick button (never shown for the leader, gated the same way the
 * server itself gates GROUP_KICK_MEMBER - the button hiding here is just
 * UX, the server re-checks everything regardless).
 */
export const MemberRow: Component<MemberRowProps> = (props) => {
  return (
    <div class={styles.memberRow}>
      <div class={styles.memberInfo}>
        <span class={styles.memberName}>
          {props.member.name ?? t()("groups.member.offline")}
          <Show when={props.isSelf}>
            <span class={styles.memberSelfBadge}>{t()("groups.member.you")}</span>
          </Show>
        </span>
        <span class={styles.memberStat}>
          {t()("groups.member.workedHours")}: {(props.member.statWorkdutySeconds / 3600).toFixed(1)}h
        </span>
      </div>

      <Show
        when={props.canManage && !props.isLeaderRow}
        fallback={<span class={styles.memberRankText}>{props.member.rankName ?? t()("groups.member.noRank")}</span>}
      >
        <select
          class={styles.rankSelect}
          value={props.member.rankId ?? ""}
          onChange={(event) => {
            const rankId = Number(event.currentTarget.value);
            if (!Number.isNaN(rankId) && rankId > 0) {
              props.onAssignRank(rankId);
            }
          }}
        >
          <option value="" disabled>
            {t()("groups.member.noRank")}
          </option>
          <For each={props.ranks}>{(rank) => <option value={rank.id}>{rank.name}</option>}</For>
        </select>
      </Show>

      <Show when={props.canManage && !props.isLeaderRow && !props.isSelf}>
        <button type="button" class={styles.kickButton} onClick={props.onKick} aria-label={t()("groups.member.kick")}>
          <UserX size={14} />
        </button>
      </Show>
    </div>
  );
};
