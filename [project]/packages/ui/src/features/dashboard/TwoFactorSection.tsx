import { type Component, Show, createSignal } from "solid-js";
import QRCode from "qrcode";
import { Button } from "@/components/ui/Button";
import { TextField, TextFieldInput, TextFieldLabel } from "@/components/ui/TextField";
import { authStore } from "@/stores/auth.store";
import { accountApi } from "@/lib/api/accountApi";
import type { ApiErrorCode } from "@/types/api";
import { t } from "@/i18n";
import styles from "./DashboardOverlay.module.scss";

/**
 * "Ustawienia konta" 2FA section - enable/disable TOTP (Google
 * Authenticator style). Mirrors the change-password form directly above
 * it in the same card: same accountForm/eyebrow classes, same
 * errorMessage()-via-i18n and inline-success-message conventions.
 *
 * Setup is two calls, never one: account.enableTwoFactor generates a
 * PENDING secret and returns it + an otpauth:// URI for the QR (never
 * enables anything), then account.confirmTwoFactorSetup proves the user
 * actually scanned/typed it correctly before the server flips it to
 * enabled - see AccountService.lua's own comment on why (a typo'd or
 * never-scanned secret must never silently "enable" and potentially
 * lock the account out).
 *
 * account().twoFactorEnabled flips automatically after a successful
 * confirm/disable - the server pushes a fresh account.updated event
 * (see AccountEndpoints.lua's confirmTwoFactorSetup/disableTwoFactor
 * handlers) which auth.store.ts already has a live handler for.
 */
export const TwoFactorSection: Component = () => {
  const account = authStore.account;

  const [step, setStep] = createSignal<"idle" | "settingUp" | "disabling">("idle");
  const [secret, setSecret] = createSignal("");
  const [qrDataUrl, setQrDataUrl] = createSignal("");
  const [confirmCode, setConfirmCode] = createSignal("");
  const [disablePassword, setDisablePassword] = createSignal("");
  const [submitting, setSubmitting] = createSignal(false);
  const [errorCode, setErrorCode] = createSignal<ApiErrorCode | null>(null);
  const [success, setSuccess] = createSignal<"enabled" | "disabled" | null>(null);

  const errorMessage = () => {
    const code = errorCode();
    if (!code) return null;
    return t()(`auth.error.${code}`);
  };

  const startSetup = async () => {
    setSubmitting(true);
    setErrorCode(null);
    setSuccess(null);
    const response = await accountApi.enableTwoFactor();
    setSubmitting(false);

    if (!response.success) {
      setErrorCode(response.error.code);
      return;
    }

    setSecret(response.data.secret);
    setQrDataUrl(await QRCode.toDataURL(response.data.otpauthUri));
    setConfirmCode("");
    setStep("settingUp");
  };

  const cancelSetup = () => {
    setStep("idle");
    setSecret("");
    setQrDataUrl("");
    setConfirmCode("");
    setErrorCode(null);
  };

  const confirmSetup = async (event: SubmitEvent) => {
    event.preventDefault();
    if (submitting()) return;

    setSubmitting(true);
    setErrorCode(null);
    const response = await accountApi.confirmTwoFactorSetup({ code: confirmCode().trim() });
    setSubmitting(false);

    if (!response.success) {
      setErrorCode(response.error.code);
      return;
    }

    setStep("idle");
    setSecret("");
    setQrDataUrl("");
    setConfirmCode("");
    setSuccess("enabled");
  };

  const startDisable = () => {
    setStep("disabling");
    setDisablePassword("");
    setErrorCode(null);
    setSuccess(null);
  };

  const cancelDisable = () => {
    setStep("idle");
    setDisablePassword("");
    setErrorCode(null);
  };

  const disable = async (event: SubmitEvent) => {
    event.preventDefault();
    if (submitting()) return;

    setSubmitting(true);
    setErrorCode(null);
    const response = await accountApi.disableTwoFactor({ currentPassword: disablePassword() });
    setSubmitting(false);

    if (!response.success) {
      setErrorCode(response.error.code);
      return;
    }

    setStep("idle");
    setDisablePassword("");
    setSuccess("disabled");
  };

  return (
    <div class={styles.accountForm}>
      <span class={styles.eyebrow}>{t()("dashboard.account.eyebrowTwoFactor")}</span>

      <Show when={step() === "idle"}>
        <div class={styles.row}>
          <span class={styles.rowLabel}>{t()("dashboard.account.eyebrowTwoFactor")}</span>
          <span class="text-sm text-foreground">
            {account()?.twoFactorEnabled
              ? t()("dashboard.account.twoFactorEnabledStatus")
              : t()("dashboard.account.twoFactorDisabledStatus")}
          </span>
        </div>

        <Show
          when={account()?.twoFactorEnabled}
          fallback={
            <Button type="button" size="sm" variant="secondary" loading={submitting()} onClick={startSetup}>
              {t()("dashboard.account.enableTwoFactorButton")}
            </Button>
          }
        >
          <Button type="button" size="sm" variant="secondary" onClick={startDisable}>
            {t()("dashboard.account.disableTwoFactorButton")}
          </Button>
        </Show>

        <Show when={success() === "enabled"}>
          <p class="text-sm text-success">{t()("dashboard.account.twoFactorEnabledSuccess")}</p>
        </Show>
        <Show when={success() === "disabled"}>
          <p class="text-sm text-success">{t()("dashboard.account.twoFactorDisabledSuccess")}</p>
        </Show>
        <Show when={errorMessage()}>
          <p class="text-sm text-danger">{errorMessage()}</p>
        </Show>
      </Show>

      <Show when={step() === "settingUp"}>
        <p class="text-sm text-muted-foreground">{t()("dashboard.account.twoFactorSetupInstructions")}</p>

        <img src={qrDataUrl()} alt="" class="size-40 self-center border border-border" />

        <div class="flex flex-col gap-1">
          <span class={styles.rowLabel}>{t()("dashboard.account.twoFactorSecretLabel")}</span>
          <code class="select-all break-all font-mono text-xs text-foreground">{secret()}</code>
        </div>

        <form class="flex flex-col gap-3" onSubmit={confirmSetup}>
          <TextField value={confirmCode()} onChange={setConfirmCode}>
            <TextFieldLabel for="dashboard-two-factor-confirm">{t()("dashboard.account.twoFactorConfirmCodeLabel")}</TextFieldLabel>
            <TextFieldInput
              id="dashboard-two-factor-confirm"
              type="text"
              inputmode="numeric"
              pattern="[0-9]*"
              autocomplete="one-time-code"
              maxLength={6}
              required
            />
          </TextField>

          <Show when={errorMessage()}>
            <p class="text-sm text-danger">{errorMessage()}</p>
          </Show>

          <div class="flex gap-2">
            <Button type="submit" size="sm" loading={submitting()} disabled={submitting() || confirmCode().length !== 6}>
              {t()("dashboard.account.twoFactorConfirmSubmit")}
            </Button>
            <Button type="button" size="sm" variant="ghost" disabled={submitting()} onClick={cancelSetup}>
              {t()("dashboard.account.twoFactorCancelSetup")}
            </Button>
          </div>
        </form>
      </Show>

      <Show when={step() === "disabling"}>
        <form class="flex flex-col gap-3" onSubmit={disable}>
          <TextField value={disablePassword()} onChange={setDisablePassword}>
            <TextFieldLabel for="dashboard-two-factor-disable-password">{t()("dashboard.account.twoFactorDisablePasswordLabel")}</TextFieldLabel>
            <TextFieldInput id="dashboard-two-factor-disable-password" type="password" autocomplete="off" required />
          </TextField>

          <Show when={errorMessage()}>
            <p class="text-sm text-danger">{errorMessage()}</p>
          </Show>

          <div class="flex gap-2">
            <Button type="submit" size="sm" loading={submitting()} disabled={submitting() || !disablePassword()}>
              {t()("dashboard.account.twoFactorDisableSubmit")}
            </Button>
            <Button type="button" size="sm" variant="ghost" disabled={submitting()} onClick={cancelDisable}>
              {t()("dashboard.account.twoFactorCancelSetup")}
            </Button>
          </div>
        </form>
      </Show>
    </div>
  );
};
