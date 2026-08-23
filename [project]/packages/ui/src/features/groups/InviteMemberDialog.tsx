import { type Component, For, onCleanup, onMount } from "solid-js";
import { UserPlus } from "lucide-solid";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/Dialog";
import { t } from "@/i18n";
import { groupStore } from "@/stores/group.store";
import styles from "./GroupPanelOverlay.module.scss";

interface InviteMemberDialogProps {
  groupId: number;
  onClose: () => void;
}

// The list is filtered by distance from the inviter server-side (see
// GroupEndpoints.lua's own INVITABLE_PLAYER_RANGE) - a fixed snapshot
// would go stale as soon as anyone walks in/out of range, so this
// re-requests it periodically while the dialog is open instead of once
// on mount. 8s: slow enough it never meaningfully loads the server
// (confirmed acceptable with the user, who asked for a 5-10s cadence),
// fast enough a moved-into-range player shows up without closing/reopening.
const REFRESH_INTERVAL_MS = 8000;

/**
 * "Add member" picker - lists online players not already in the group,
 * within range of the inviter (server-filtered, see GroupEndpoints.lua's
 * own GROUP_REQUEST_INVITABLE_PLAYERS handler) and lets a manage_members
 * member send one an invite. Does NOT add the player directly - the
 * target still has to accept via GroupInviteToast.tsx, see
 * group.store.ts's pendingInvites slice.
 */
export const InviteMemberDialog: Component<InviteMemberDialogProps> = (props) => {
  onMount(() => {
    groupStore.requestInvitablePlayers(props.groupId);
    const interval = window.setInterval(() => groupStore.requestInvitablePlayers(props.groupId), REFRESH_INTERVAL_MS);
    onCleanup(() => window.clearInterval(interval));
  });

  const players = () => groupStore.invitablePlayersFor(props.groupId);

  return (
    <Dialog open onOpenChange={(open) => !open && props.onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t()("groups.invite.title")}</DialogTitle>
        </DialogHeader>

        <div class={styles.listWrap}>
          <For each={players()} fallback={<div class={styles.empty}>{t()("groups.invite.empty")}</div>}>
            {(player) => (
              <button
                type="button"
                class={styles.playerRow}
                onClick={() => {
                  groupStore.invitePlayer(props.groupId, player.accountId);
                  props.onClose();
                }}
              >
                <span class={styles.playerRowName}>{player.name}</span>
                <UserPlus size={14} />
              </button>
            )}
          </For>
        </div>
      </DialogContent>
    </Dialog>
  );
};
