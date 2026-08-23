import { createSignal } from "solid-js";
import { createStore, reconcile } from "solid-js/store";
import type {
  GroupDutyStartedPayload,
  GroupInvite,
  GroupMembership,
  GroupMembersPayload,
  GroupPermissions,
  InvitablePlayersPayload,
} from "@/types/group";
import { mta } from "@/lib/mta/MtaBridge";

const [memberships, setMemberships] = createStore<GroupMembership[]>([]);
// keyed by groupId - only populated for whichever group is currently open in the panel's Members tab
const [membersByGroup, setMembersByGroup] = createStore<Record<number, GroupMembersPayload["members"]>>({});
// keyed by groupId - only populated for whichever group currently has the "Add member" picker open
const [invitablePlayersByGroup, setInvitablePlayersByGroup] = createStore<Record<number, InvitablePlayersPayload["players"]>>({});
// The local player's own pending invites (received while online, or bulk-loaded on spawn) - drives GroupInviteToast.tsx.
const [pendingInvites, setPendingInvites] = createStore<GroupInvite[]>([]);

const [dutyActive, setDutyActive] = createSignal(false);
const [dutyInfo, setDutyInfo] = createSignal<GroupDutyStartedPayload | null>(null);
const [dutyTotalSeconds, setDutyTotalSeconds] = createSignal(0);

function requestMembers(groupId: number) {
  mta.notify("groups:requestMembers", groupId);
}

function createRank(groupId: number, data: { name: string; skin: number; hourlyReward: number; permissions: GroupPermissions; sortOrder: number }) {
  mta.notify("groups:createRank", { groupId, ...data });
}

function updateRank(rankId: number, data: Partial<{ name: string; skin: number; hourlyReward: number; permissions: GroupPermissions; sortOrder: number }>) {
  mta.notify("groups:updateRank", { rankId, ...data });
}

function deleteRank(rankId: number) {
  mta.notify("groups:deleteRank", { rankId });
}

function assignMemberRank(memberId: number, rankId: number) {
  mta.notify("groups:assignMemberRank", { memberId, rankId });
}

function kickMember(memberId: number) {
  mta.notify("groups:kickMember", { memberId });
}

function leaveGroup(groupId: number) {
  mta.notify("groups:leave", { groupId });
}

function requestInvitablePlayers(groupId: number) {
  mta.notify("groups:requestInvitablePlayers", groupId);
}

function invitePlayer(groupId: number, accountId: number) {
  mta.notify("groups:invitePlayer", { groupId, accountId });
}

function acceptInvite(inviteId: number) {
  mta.notify("groups:acceptInvite", inviteId);
  // Optimistic local removal - the real confirmation arrives via a fresh
  // groups.mine push, but the invite itself won't be re-sent (it's
  // deleted server-side on accept), so nothing would otherwise clear it
  // from this list if the player already closed the toast.
  setPendingInvites((current) => current.filter((invite) => invite.inviteId !== inviteId));
}

function declineInvite(inviteId: number) {
  mta.notify("groups:declineInvite", inviteId);
  setPendingInvites((current) => current.filter((invite) => invite.inviteId !== inviteId));
}

export const groupStore = {
  memberships: () => memberships,
  membersFor: (groupId: number) => membersByGroup[groupId] ?? [],
  invitablePlayersFor: (groupId: number) => invitablePlayersByGroup[groupId] ?? [],
  pendingInvites: () => pendingInvites,
  duty: {
    active: dutyActive,
    info: dutyInfo,
    totalSeconds: dutyTotalSeconds,
  },
  requestMembers,
  createRank,
  updateRank,
  deleteRank,
  assignMemberRank,
  kickMember,
  leaveGroup,
  requestInvitablePlayers,
  invitePlayer,
  acceptInvite,
  declineInvite,
};

mta.on("groups.mine", (data) => {
  // No stable top-level id to reconcile by (id lives nested under
  // .member.id/.group.id) - a full replace is fine here, this only
  // arrives on panel open + after a mutation, never on a hot loop.
  setMemberships(data as GroupMembership[]);
});

mta.on("groups.members", (data) => {
  const payload = data as GroupMembersPayload;
  setMembersByGroup(payload.groupId, payload.members);
});

mta.on("groups.dutyStarted", (data) => {
  const payload = data as GroupDutyStartedPayload;
  setDutyInfo(payload);
  setDutyTotalSeconds(payload.totalSeconds);
  setDutyActive(true);
});

mta.on("groups.dutyEnded", () => {
  setDutyActive(false);
  setDutyInfo(null);
});

mta.on("groups.dutySync", (data) => {
  const payload = data as { totalSeconds: number };
  setDutyTotalSeconds(payload.totalSeconds);
});

mta.on("groups.invitablePlayers", (data) => {
  const payload = data as InvitablePlayersPayload;
  setInvitablePlayersByGroup(payload.groupId, payload.players);
});

mta.on("groups.inviteReceived", (data) => {
  const invite = data as GroupInvite;
  setPendingInvites((current) => (current.some((existing) => existing.inviteId === invite.inviteId) ? current : [...current, invite]));
});

mta.on("groups.invites", (data) => {
  setPendingInvites(reconcile(data as GroupInvite[], { key: "inviteId" }));
});
