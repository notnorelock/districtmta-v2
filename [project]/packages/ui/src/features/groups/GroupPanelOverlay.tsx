import { type Component, For, Show, createEffect, createMemo, createSignal } from "solid-js";
import { Plus, Shield, UserPlus, Users } from "lucide-solid";
import { Overlay } from "@/components/common/Overlay";
import { Button } from "@/components/ui/Button";
import { t } from "@/i18n";
import { groupStore } from "@/stores/group.store";
import type { GroupRank } from "@/types/group";
import { MemberRow } from "./MemberRow";
import { RankEditor } from "./RankEditor";
import { InviteMemberDialog } from "./InviteMemberDialog";
import styles from "./GroupPanelOverlay.module.scss";

type PanelTab = "members" | "ranks";

/**
 * Group management panel (G) - side rail of the player's own groups
 * (multi-membership is allowed, see docs/GroupService.lua's own module
 * comment), Members/Ranks tabs for whichever group is currently
 * selected, VehicleStorageOverlay.tsx-shaped (small centered panel, not
 * full-screen like WorldMapOverlay.tsx - a roster of a few dozen members
 * doesn't need it). Opened/closed by GroupPanelState.lua's own G keybind
 * toggle, own "groupPanel" overlay key.
 */
export const GroupPanelOverlay: Component = () => {
  const [selectedGroupId, setSelectedGroupId] = createSignal<number | null>(null);
  const [tab, setTab] = createSignal<PanelTab>("members");
  const [editingRank, setEditingRank] = createSignal<GroupRank | "new" | null>(null);
  const [invitingMember, setInvitingMember] = createSignal(false);

  const memberships = groupStore.memberships;

  // Keep a valid selection as memberships arrive/change (panel opens with
  // nothing selected yet, or the previously-selected group was left/deleted).
  createEffect(() => {
    const list = memberships();
    if (list.length === 0) {
      setSelectedGroupId(null);
      return;
    }
    if (!list.some((entry) => entry.group.id === selectedGroupId())) {
      setSelectedGroupId(list[0]!.group.id);
    }
  });

  const selected = createMemo(() => memberships().find((entry) => entry.group.id === selectedGroupId()) ?? null);

  createEffect(() => {
    const groupId = selectedGroupId();
    if (groupId !== null && tab() === "members") {
      groupStore.requestMembers(groupId);
    }
  });

  const members = createMemo(() => {
    const groupId = selectedGroupId();
    return groupId !== null ? groupStore.membersFor(groupId) : [];
  });

  const canManageMembers = createMemo(() => selected()?.permissions.manage_members === true || selected()?.permissions.is_leader === true);
  const canManageRanks = createMemo(() => selected()?.permissions.manage_ranks === true || selected()?.permissions.is_leader === true);

  return (
    <Overlay name="groupPanel" transitionName="groupPanel">
      <div class={styles.root}>
        <div class={styles.panel}>
          <div class={styles.groupRail}>
            <For each={memberships()} fallback={<div class={styles.empty}>{t()("groups.noGroups")}</div>}>
              {(entry) => (
                <button
                  type="button"
                  class={`${styles.groupTab} ${selectedGroupId() === entry.group.id ? styles.groupTabActive : ""}`}
                  style={{ "--group-color": entry.group.color ?? typeColor(entry.group.type) }}
                  onClick={() => setSelectedGroupId(entry.group.id)}
                >
                  <span class={styles.groupTabDot} />
                  <span class={styles.groupTabLabel}>{entry.group.name}</span>
                </button>
              )}
            </For>
          </div>

          <Show when={selected()} fallback={<div class={styles.mainEmpty}>{t()("groups.noGroups")}</div>}>
            {(entry) => (
              <div class={styles.main}>
                <div class={styles.header}>
                  <div class={styles.headerInfo}>
                    <span class={styles.title}>{entry().group.name}</span>
                    <span class={styles.subtitle}>{t()(`groups.type.${entry().group.type}`)}</span>
                  </div>
                  <div class={styles.tabs}>
                    <button
                      type="button"
                      class={`${styles.tabButton} ${tab() === "members" ? styles.tabButtonActive : ""}`}
                      onClick={() => setTab("members")}
                    >
                      <Users size={14} />
                      {t()("groups.tab.members")}
                    </button>
                    <button
                      type="button"
                      class={`${styles.tabButton} ${tab() === "ranks" ? styles.tabButtonActive : ""}`}
                      onClick={() => setTab("ranks")}
                    >
                      <Shield size={14} />
                      {t()("groups.tab.ranks")}
                    </button>
                  </div>
                </div>

                <Show when={tab() === "members"}>
                  <div class={styles.listWrap}>
                    <Show when={canManageMembers()}>
                      <Button type="button" variant="secondary" size="sm" class={styles.addMemberButton} onClick={() => setInvitingMember(true)}>
                        <UserPlus size={14} />
                        {t()("groups.member.invite")}
                      </Button>
                    </Show>
                    <For each={members()} fallback={<div class={styles.empty}>{t()("groups.noMembers")}</div>}>
                      {(member) => (
                        <MemberRow
                          member={member}
                          ranks={entry().group.ranks}
                          isSelf={member.accountId === entry().member.accountId}
                          isLeaderRow={member.rankId !== null && entry().group.ranks.find((r) => r.id === member.rankId)?.permissions.is_leader === true}
                          canManage={canManageMembers()}
                          onAssignRank={(rankId) => groupStore.assignMemberRank(member.id, rankId)}
                          onKick={() => groupStore.kickMember(member.id)}
                        />
                      )}
                    </For>
                  </div>
                </Show>

                <Show when={tab() === "ranks"}>
                  <div class={styles.listWrap}>
                    <For each={entry().group.ranks} fallback={<div class={styles.empty}>{t()("groups.noRanks")}</div>}>
                      {(rank) => (
                        <button
                          type="button"
                          class={styles.rankRow}
                          disabled={!canManageRanks()}
                          onClick={() => canManageRanks() && setEditingRank(rank)}
                        >
                          <span class={styles.rankRowName}>{rank.name}</span>
                          <span class={styles.rankRowMeta}>
                            {t()("groups.rank.hourlyReward")}: ${rank.hourlyReward}
                          </span>
                        </button>
                      )}
                    </For>
                    <Show when={canManageRanks()}>
                      <Button type="button" variant="secondary" size="sm" class={styles.addRankButton} onClick={() => setEditingRank("new")}>
                        <Plus size={14} />
                        {t()("groups.rank.create")}
                      </Button>
                    </Show>
                  </div>
                </Show>
              </div>
            )}
          </Show>
        </div>
      </div>

      <Show when={selected()}>
        {(entry) => (
          <>
            <Show when={editingRank()}>
              {(rank) => (
                <RankEditor
                  groupId={entry().group.id}
                  rank={rank() === "new" ? null : (rank() as GroupRank)}
                  existingRankCount={entry().group.ranks.length}
                  onClose={() => setEditingRank(null)}
                />
              )}
            </Show>
            <Show when={invitingMember()}>
              <InviteMemberDialog groupId={entry().group.id} onClose={() => setInvitingMember(false)} />
            </Show>
          </>
        )}
      </Show>
    </Overlay>
  );
};

function typeColor(type: string): string {
  if (type === "gang") return "#e74c3c";
  if (type === "fraction") return "#f2b84a";
  return "#3498db";
}
