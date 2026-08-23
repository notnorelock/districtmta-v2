/** Mirrors GroupEndpoints.lua's own toMemberEntry - one row in a group's roster. */
export interface GroupMember {
  id: number;
  accountId: number;
  /** Null when the account is currently offline - v1 has no bridge to resolve an offline account's login, see GroupEndpoints.lua's own onlinePlayerNameForAccount comment. */
  name: string | null;
  rankId: number | null;
  rankName: string | null;
  sortOrder: number | null;
  statWorkdutySeconds: number;
  lastPayoutAt: string | null;
}

/** Mirrors GroupEndpoints.lua's own toGroupEntry's `ranks` array entries. */
export interface GroupRank {
  id: number;
  name: string;
  skin: number;
  hourlyReward: number;
  permissions: GroupPermissions;
  sortOrder: number;
}

/** JSON permission keys a rank can hold - see GroupRankRepository.lua's own permissions column. */
export interface GroupPermissions {
  is_leader?: boolean;
  manage_members?: boolean;
  manage_ranks?: boolean;
}

export type GroupType = "gang" | "organization" | "fraction";

/** Mirrors GroupEndpoints.lua's own toGroupEntry. */
export interface Group {
  id: number;
  name: string;
  type: GroupType;
  color: string | null;
  hasDutyPosition: boolean;
  ranks: GroupRank[];
}

/** One entry of the array GroupEndpoints.lua's sendMine pushes as PUSH_GROUP_MINE. */
export interface GroupMembership {
  group: Group;
  member: GroupMember;
  permissions: GroupPermissions;
}

/** Mirrors GroupEndpoints.lua's sendMembers own PUSH_GROUP_MEMBERS payload. */
export interface GroupMembersPayload {
  groupId: number;
  members: GroupMember[];
}

/** Mirrors GroupDutyService.lua's Events.GROUP_DUTY_STARTED payload. */
export interface GroupDutyStartedPayload {
  groupName: string;
  groupType: GroupType;
  rankName: string;
  totalSeconds: number;
}

/** One online player not already in the group, for the "Add member" picker - mirrors GroupEndpoints.lua's own GROUP_INVITABLE_PLAYERS_RECEIVED entries. */
export interface InvitablePlayer {
  accountId: number;
  name: string;
}

/** Mirrors GroupEndpoints.lua's own GROUP_INVITABLE_PLAYERS_RECEIVED payload. */
export interface InvitablePlayersPayload {
  groupId: number;
  players: InvitablePlayer[];
}

/** Mirrors GroupEndpoints.lua's own toInviteEntry - a pending invite, either pushed live (GROUP_INVITE_RECEIVED) or listed in bulk (GROUP_INVITES_RECEIVED). */
export interface GroupInvite {
  inviteId: number;
  groupId: number;
  groupName: string;
  groupType: GroupType;
  invitedByName: string;
}

/** Mirrors GroupVehicleService.lua's own toVehicleEntries - one group-owned vehicle and which ranks may use it. */
export interface GroupVehicle {
  id: number;
  model: number;
  allowedRankIds: number[];
}

/** Mirrors GroupVehicleService.lua's own GROUP_VEHICLES_RECEIVED payload. */
export interface GroupVehiclesPayload {
  groupId: number;
  vehicles: GroupVehicle[];
}
