import { type Component, Show, createSignal } from "solid-js";
import { Button } from "@/components/ui/Button";
import { TextField, TextFieldInput, TextFieldLabel } from "@/components/ui/TextField";
import { authStore } from "@/stores/auth.store";
import { accountApi } from "@/lib/api/accountApi";
import { AccountRole } from "@/types/account";
import type { ApiErrorCode } from "@/types/api";
import { t } from "@/i18n";
import styles from "./DashboardOverlay.module.scss";

// 6-entry map used in exactly one place - not extracted to a shared
// module, matching this project's bias against premature abstraction.
const ROLE_LABEL: Record<number, string> = {
  [AccountRole.PLAYER]: "Gracz",
  [AccountRole.VETERAN]: "Weteran",
  [AccountRole.SUPPORTER]: "Pomocnik",
  [AccountRole.MODERATOR]: "Moderator",
  [AccountRole.ADMINISTRATOR]: "Administrator",
  [AccountRole.RCON]: "RCON",
  [AccountRole.BOARD]: "Zarząd",
};

/**
 * Account info readout (read side: authStore.account() directly, zero
 * new fetches) + change-password form. Server re-verifies the current
 * password and re-validates the new one itself (see
 * AccountService.changePassword) - this form never trusts its own
 * client-side checks beyond the confirm-mismatch UX guard.
 */
export const AccountTab: Component = () => {
  const account = authStore.account;

  const [currentPassword, setCurrentPassword] = createSignal("");
  const [newPassword, setNewPassword] = createSignal("");
  const [confirmPassword, setConfirmPassword] = createSignal("");
  const [submitting, setSubmitting] = createSignal(false);
  const [mismatch, setMismatch] = createSignal(false);
  const [errorCode, setErrorCode] = createSignal<ApiErrorCode | null>(null);
  const [success, setSuccess] = createSignal(false);

  const errorMessage = () => {
    if (mismatch()) return t()("auth.register.passwordMismatch");
    const code = errorCode();
    if (!code) return null;
    return t()(`auth.error.${code}`);
  };

  const handleSubmit = async (event: SubmitEvent) => {
    event.preventDefault();
    if (submitting()) return;

    setSuccess(false);
    setErrorCode(null);

    if (newPassword() !== confirmPassword()) {
      setMismatch(true);
      return;
    }
    setMismatch(false);

    setSubmitting(true);
    const response = await accountApi.changePassword({
      currentPassword: currentPassword(),
      newPassword: newPassword(),
    });
    setSubmitting(false);

    if (!response.success) {
      setErrorCode(response.error.code);
      return;
    }

    setCurrentPassword("");
    setNewPassword("");
    setConfirmPassword("");
    setSuccess(true);
  };

  return (
    <div class={styles.listWrap}>
      <Show when={account()}>
        {(acc) => (
          <>
            <div class={styles.row}>
              <span class={styles.rowLabel}>{t()("dashboard.account.login")}</span>
              <span>{acc().login}</span>
            </div>
            <div class={styles.row}>
              <span class={styles.rowLabel}>{t()("dashboard.account.email")}</span>
              <span>{acc().email}</span>
            </div>
            <div class={styles.row}>
              <span class={styles.rowLabel}>{t()("dashboard.account.role")}</span>
              <span>{ROLE_LABEL[acc().role] ?? acc().role}</span>
            </div>
          </>
        )}
      </Show>

      <form class="flex flex-col gap-3 px-4 py-3" onSubmit={handleSubmit}>
        <span class={styles.rowLabel}>{t()("dashboard.account.changePassword")}</span>

        <TextField value={currentPassword()} onChange={setCurrentPassword}>
          <TextFieldLabel for="dashboard-current-password">{t()("dashboard.account.currentPassword")}</TextFieldLabel>
          <TextFieldInput id="dashboard-current-password" type="password" autocomplete="off" minLength={8} maxLength={128} required />
        </TextField>

        <TextField value={newPassword()} onChange={setNewPassword}>
          <TextFieldLabel for="dashboard-new-password">{t()("dashboard.account.newPassword")}</TextFieldLabel>
          <TextFieldInput id="dashboard-new-password" type="password" autocomplete="off" minLength={8} maxLength={128} required />
        </TextField>

        <TextField value={confirmPassword()} onChange={setConfirmPassword}>
          <TextFieldLabel for="dashboard-confirm-password">{t()("dashboard.account.confirmNewPassword")}</TextFieldLabel>
          <TextFieldInput id="dashboard-confirm-password" type="password" autocomplete="off" minLength={8} maxLength={128} required />
        </TextField>

        <Show when={errorMessage()}>
          <p class="text-sm text-danger">{errorMessage()}</p>
        </Show>
        <Show when={success()}>
          <p class="text-sm text-success">{t()("dashboard.account.passwordChanged")}</p>
        </Show>

        <Button
          type="submit"
          size="sm"
          loading={submitting()}
          disabled={submitting() || !currentPassword() || !newPassword() || !confirmPassword()}
        >
          {submitting() ? t()("auth.login.submitting") : t()("dashboard.account.changePasswordSubmit")}
        </Button>
      </form>
    </div>
  );
};
