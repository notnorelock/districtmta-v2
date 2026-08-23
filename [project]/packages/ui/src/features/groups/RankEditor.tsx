import { type Component, createMemo, createSignal } from "solid-js";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/Dialog";
import { Button } from "@/components/ui/Button";
import { Checkbox, CheckboxLabel } from "@/components/ui/Checkbox";
import { TextField, TextFieldInput, TextFieldLabel } from "@/components/ui/TextField";
import { t } from "@/i18n";
import { groupStore } from "@/stores/group.store";
import { authStore } from "@/stores/auth.store";
import { AccountRole } from "@/types/account";
import type { GroupRank } from "@/types/group";
import styles from "./RankEditor.module.scss";

interface RankEditorProps {
  groupId: number;
  /** null = creating a new rank, otherwise editing this one. */
  rank: GroupRank | null;
  /** Used to block deleting the group's only remaining rank, mirroring GroupEndpoints.lua's own GROUP_DELETE_RANK check. */
  existingRankCount: number;
  onClose: () => void;
}

/**
 * Create/edit-rank dialog - name, skin model id, hourly duty reward, sort
 * order (lower = more senior), and a checkbox grid for the JSON
 * permission keys GroupRankRepository.lua's permissions column holds.
 * The server re-validates manage_ranks + seniority on every mutation
 * regardless (see GroupEndpoints.lua) - this form only shapes the request.
 *
 * The LEADER rank (permissions.is_leader) is special-cased: its
 * permission checkboxes are always locked (a leader/manage_ranks member
 * editing their own group's leader rank can never strip is_leader off it -
 * server-enforced in GroupEndpoints.lua's own GROUP_UPDATE_RANK handler,
 * this is purely the matching UI treatment), and its hourlyReward field is
 * ALSO locked unless the viewer is a server Administrator+ - confirmed
 * with the user: only an admin decides a faction leader's own payout, not
 * the leader themselves. Administrator+ is the client-side equivalent of
 * Permissions.Bit.MANAGE_GROUPS (folded into ADMINISTRATOR_PERMISSIONS in
 * core/server/accounts/Permissions.lua) - this project has no client-side
 * bitmask check, so role >= ADMINISTRATOR is the closest available proxy,
 * same as every other role-gated UI affordance in this codebase.
 */
export const RankEditor: Component<RankEditorProps> = (props) => {
  const [name, setName] = createSignal(props.rank?.name ?? "");
  const [skin, setSkin] = createSignal(props.rank?.skin ?? 0);
  const [hourlyReward, setHourlyReward] = createSignal(props.rank?.hourlyReward ?? 0);
  const [sortOrder, setSortOrder] = createSignal(props.rank?.sortOrder ?? 1);
  const [manageMembers, setManageMembers] = createSignal(props.rank?.permissions.manage_members ?? false);
  const [manageRanks, setManageRanks] = createSignal(props.rank?.permissions.manage_ranks ?? false);

  const isLeaderRank = () => props.rank?.permissions.is_leader === true;
  const isAdmin = createMemo(() => (authStore.account()?.role ?? AccountRole.PLAYER) >= AccountRole.ADMINISTRATOR);
  const permissionsLocked = () => isLeaderRank();
  const hourlyRewardLocked = () => isLeaderRank() && !isAdmin();

  const canDelete = () => props.rank !== null && props.existingRankCount > 1;

  const submit = () => {
    const data = {
      name: name(),
      skin: skin(),
      hourlyReward: hourlyReward(),
      sortOrder: sortOrder(),
      permissions: { manage_members: manageMembers(), manage_ranks: manageRanks() },
    };

    if (props.rank) {
      groupStore.updateRank(props.rank.id, data);
    } else {
      groupStore.createRank(props.groupId, data);
    }
    props.onClose();
  };

  const remove = () => {
    if (props.rank) {
      groupStore.deleteRank(props.rank.id);
    }
    props.onClose();
  };

  return (
    <Dialog open onOpenChange={(open) => !open && props.onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{props.rank ? t()("groups.rank.editTitle") : t()("groups.rank.createTitle")}</DialogTitle>
        </DialogHeader>

        <div class={styles.form}>
          <TextField>
            <TextFieldLabel>{t()("groups.rank.name")}</TextFieldLabel>
            <TextFieldInput value={name()} onInput={(event) => setName(event.currentTarget.value)} />
          </TextField>

          <div class={styles.row}>
            <TextField>
              <TextFieldLabel>{t()("groups.rank.skin")}</TextFieldLabel>
              <TextFieldInput
                type="number"
                value={skin()}
                onInput={(event) => setSkin(Number(event.currentTarget.value) || 0)}
              />
            </TextField>

            <TextField>
              <TextFieldLabel>{t()("groups.rank.hourlyReward")}</TextFieldLabel>
              <TextFieldInput
                type="number"
                value={hourlyReward()}
                disabled={hourlyRewardLocked()}
                onInput={(event) => setHourlyReward(Number(event.currentTarget.value) || 0)}
              />
            </TextField>

            <TextField>
              <TextFieldLabel>{t()("groups.rank.sortOrder")}</TextFieldLabel>
              <TextFieldInput
                type="number"
                value={sortOrder()}
                onInput={(event) => setSortOrder(Number(event.currentTarget.value) || 0)}
              />
            </TextField>
          </div>

          <div class={styles.permissions}>
            <Checkbox checked={manageMembers()} disabled={permissionsLocked()} onChange={setManageMembers}>
              <CheckboxLabel>{t()("groups.rank.permission.manageMembers")}</CheckboxLabel>
            </Checkbox>
            <Checkbox checked={manageRanks()} disabled={permissionsLocked()} onChange={setManageRanks}>
              <CheckboxLabel>{t()("groups.rank.permission.manageRanks")}</CheckboxLabel>
            </Checkbox>
          </div>
        </div>

        <DialogFooter>
          {canDelete() && (
            <Button type="button" variant="destructive" onClick={remove}>
              {t()("groups.rank.delete")}
            </Button>
          )}
          <Button type="button" variant="gradient" onClick={submit}>
            {t()("groups.rank.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
