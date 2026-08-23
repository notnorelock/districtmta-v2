import { type Component, For } from "solid-js";
import { TransitionGroup } from "solid-transition-group";
import { Check, Users, X } from "lucide-solid";
import { t } from "@/i18n";
import { groupStore } from "@/stores/group.store";
import styles from "./GroupInviteToast.module.scss";

/**
 * Pending group-invite prompt(s) - always mounted (not gated behind any
 * "groupPanel"/other Overlay key, same reasoning as DutyIndicator.tsx),
 * purely driven by group.store.ts's pendingInvites slice, which
 * GroupPanelState.lua's own GROUP_INVITE_RECEIVED/GROUP_INVITES pushes
 * feed - so an invite surfaces here whether or not the player has the
 * group panel (G) open at all. Docked top-center (not bottom-right like
 * DutyIndicator/HudBar) so it never collides with either.
 */
export const GroupInviteToast: Component = () => {
  return (
    <div class={styles.dock}>
      <TransitionGroup
        enterActiveClass={styles.cardEnterActive}
        exitActiveClass={styles.cardExitActive}
        enterClass={styles.cardEnterFrom}
        exitToClass={styles.cardExitTo}
        moveClass={styles.cardMove}
      >
        <For each={groupStore.pendingInvites()}>
          {(invite) => (
            <div class={styles.card}>
              <div class={styles.icon}>
                <Users size={16} />
              </div>
              <div class={styles.info}>
                <span class={styles.title}>{t()("groups.invite.prompt").replace("{group}", invite.groupName)}</span>
                <span class={styles.subtitle}>{t()("groups.invite.from").replace("{name}", invite.invitedByName)}</span>
              </div>
              <div class={styles.actions}>
                <button
                  type="button"
                  class={styles.acceptButton}
                  onClick={() => groupStore.acceptInvite(invite.inviteId)}
                  aria-label={t()("groups.invite.accept")}
                >
                  <Check size={14} />
                </button>
                <button
                  type="button"
                  class={styles.declineButton}
                  onClick={() => groupStore.declineInvite(invite.inviteId)}
                  aria-label={t()("groups.invite.decline")}
                >
                  <X size={14} />
                </button>
              </div>
            </div>
          )}
        </For>
      </TransitionGroup>
    </div>
  );
};
