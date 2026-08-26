import { type Component, Show } from "solid-js";
import { Button } from "@/components/ui/Button";
import { TextField, TextFieldInput, TextFieldLabel } from "@/components/ui/TextField";
import { authStore } from "@/stores/auth.store";
import { useTwoFactorSetup } from "./useTwoFactorSetup";
import { t } from "@/i18n";

const submitButtonClass = "auth-panel__submit mt-2 h-auto w-full py-4 font-mono text-xs font-bold uppercase tracking-widest";

/**
 * Post-registration "secure your account" step - shown once, right after a
 * successful registration, before the player can proceed to spawn-select
 * (see auth.store.ts's "securingAccount" phase and App.tsx's <Match>
 * ordering, which is load-bearing: the server pushes SPAWN_SELECT_OPEN
 * immediately and unconditionally after registration, so this phase check
 * is the ONLY thing preventing SpawnSelectView from racing ahead of this
 * screen). Offers to configure TOTP 2FA (reusing the same
 * enable->confirm proof-of-possession flow as the dashboard's
 * TwoFactorSection.tsx, via the shared useTwoFactorSetup hook) or skip
 * entirely - either path finishes via authStore.finishSecuringAccount(),
 * which never itself calls any account.* endpoint, it only flips the
 * local phase forward.
 */
export const SecureAccountStep: Component = () => {
  const { step, secret, qrDataUrl, confirmCode, setConfirmCode, submitting, errorCode, startSetup, cancelSetup, confirmSetup } = useTwoFactorSetup();

  const errorMessage = () => {
    const code = errorCode();
    return code ? t()(`auth.error.${code}`) : null;
  };

  const handleConfirm = (event: SubmitEvent) => confirmSetup(event, () => authStore.finishSecuringAccount());

  const handleSkip = () => authStore.finishSecuringAccount();

  return (
    <div class="flex h-full w-full items-center justify-center bg-background/60">
      <div class="flex w-full max-w-md flex-col gap-6 px-12 py-10">
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-foreground">{t()("auth.secureAccount.title")}</h1>
          <p class="mt-1 text-sm text-muted-foreground">{t()("auth.secureAccount.subtitle")}</p>
        </div>

        <Show
          when={step() === "settingUp"}
          fallback={
            <div class="flex flex-col gap-4">
              <Button type="button" variant="gradient" class={submitButtonClass} loading={submitting()} onClick={startSetup}>
                {t()("auth.secureAccount.enableButton")}
              </Button>
              <Button type="button" variant="ghost" onClick={handleSkip} disabled={submitting()}>
                {t()("auth.secureAccount.skipButton")}
              </Button>
            </div>
          }
        >
          <div class="flex flex-col gap-4">
            <p class="text-sm text-muted-foreground">{t()("dashboard.account.twoFactorSetupInstructions")}</p>

            <img src={qrDataUrl()} alt="" class="size-40 self-center border border-border" />

            <div class="flex flex-col gap-1">
              <span class="font-mono text-2xs font-bold uppercase tracking-widest text-accent-indigo/70">
                {t()("dashboard.account.twoFactorSecretLabel")}
              </span>
              <code class="select-all break-all font-mono text-xs text-foreground">{secret()}</code>
            </div>

            <form class="flex flex-col gap-4" onSubmit={handleConfirm}>
              <TextField value={confirmCode()} onChange={setConfirmCode} class="gap-2">
                <TextFieldLabel
                  for="secure-account-confirm"
                  class="select-none font-mono text-2xs font-bold uppercase tracking-widest text-accent-indigo/70"
                >
                  {t()("dashboard.account.twoFactorConfirmCodeLabel")}
                </TextFieldLabel>
                <TextFieldInput
                  id="secure-account-confirm"
                  type="text"
                  inputmode="numeric"
                  pattern="[0-9]*"
                  autocomplete="one-time-code"
                  maxLength={6}
                  autofocus
                  class="h-auto border-accent-indigo/20 bg-black/60 px-4 py-3.5 backdrop-blur-md focus-visible:outline-none focus-visible:ring-0 focus-visible:ring-offset-0 focus-visible:border-accent-indigo/60"
                />
              </TextField>

              <Show when={errorMessage()}>
                <p class="text-sm text-danger">{errorMessage()}</p>
              </Show>

              <Button
                type="submit"
                variant="gradient"
                class={submitButtonClass}
                loading={submitting()}
                disabled={submitting() || confirmCode().length !== 6}
              >
                {t()("dashboard.account.twoFactorConfirmSubmit")}
              </Button>
              <Button type="button" variant="ghost" onClick={cancelSetup} disabled={submitting()}>
                {t()("dashboard.account.twoFactorCancelSetup")}
              </Button>
            </form>
          </div>
        </Show>
      </div>
    </div>
  );
};
