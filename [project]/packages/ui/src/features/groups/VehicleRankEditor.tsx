import { type Component, For, createSignal } from "solid-js";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/Dialog";
import { Button } from "@/components/ui/Button";
import { Checkbox, CheckboxLabel } from "@/components/ui/Checkbox";
import { t } from "@/i18n";
import { groupStore } from "@/stores/group.store";
import type { GroupRank, GroupVehicle } from "@/types/group";
import styles from "./RankEditor.module.scss";

interface VehicleRankEditorProps {
  vehicle: GroupVehicle;
  ranks: GroupRank[];
  onClose: () => void;
}

/**
 * "Which ranks may use this vehicle" editor - a checkbox per group rank,
 * submits the ENTIRE new allowlist (GroupVehicleRankRepository.lua's own
 * setForVehicle replaces the whole list, not a per-rank toggle) - see
 * GroupVehicleService.lua's own GROUP_SET_VEHICLE_RANKS handler.
 */
export const VehicleRankEditor: Component<VehicleRankEditorProps> = (props) => {
  const [selected, setSelected] = createSignal(new Set(props.vehicle.allowedRankIds));

  const toggle = (rankId: number) => {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(rankId)) {
        next.delete(rankId);
      } else {
        next.add(rankId);
      }
      return next;
    });
  };

  const submit = () => {
    groupStore.setVehicleRanks(props.vehicle.id, [...selected()]);
    props.onClose();
  };

  return (
    <Dialog open onOpenChange={(open) => !open && props.onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t()("groups.vehicle.ranksTitle")}</DialogTitle>
        </DialogHeader>

        <div class={styles.permissions}>
          <For each={props.ranks} fallback={<div>{t()("groups.noRanks")}</div>}>
            {(rank) => (
              <Checkbox checked={selected().has(rank.id)} onChange={() => toggle(rank.id)}>
                <CheckboxLabel>{rank.name}</CheckboxLabel>
              </Checkbox>
            )}
          </For>
        </div>

        <DialogFooter>
          <Button type="button" variant="gradient" onClick={submit}>
            {t()("groups.rank.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
