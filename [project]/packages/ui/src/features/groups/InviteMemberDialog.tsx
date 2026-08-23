import { type Component, For, createEffect } from "solid-js";
import { UserPlus } from "lucide-solid";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/Dialog";
import { t } from "@/i18n";
import { groupStore } from "@/stores/group.store";
import styles from "./GroupPanelOverlay.module.scss";

interface InviteMemberDialogProps {
  groupId: number;
  onClose: () => void;
}

/**
 * "Add member" picker - lists online players not already in the group
 * (server-filtered, see GroupEndpoints.lua's own GROUP_REQUEST_INVITABLE_PLAYERS
 * handler) and lets a manage_members member send one an invite. Does NOT
 * add the player directly - the target still has to accept via
 * GroupInviteToast.tsx, see group.store.ts's pendingInvites slice.
 */
export const InviteMemberDialog: Component<InviteMemberDialogProps> = (props) => {
  createEffect(() => {
    groupStore.requestInvitablePlayers(props.groupId);
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
