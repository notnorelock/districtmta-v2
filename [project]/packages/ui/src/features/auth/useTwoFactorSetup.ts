import { createSignal } from "solid-js";
import QRCode from "qrcode";
import { accountApi } from "@/lib/api/accountApi";
import type { ApiErrorCode } from "@/types/api";

/**
 * Shared enable->confirm TOTP setup logic - the proof-of-possession
 * two-call flow (account.enableTwoFactor generates a PENDING secret,
 * account.confirmTwoFactorSetup proves the user actually scanned/typed it
 * correctly before the server flips it to enabled - see AccountService.lua's
 * own comment on why a typo'd/never-scanned secret must never silently
 * "enable"). Extracted so the dashboard's TwoFactorSection.tsx and the
 * post-registration SecureAccountStep.tsx share one implementation instead
 * of two copies that could drift - only the surrounding chrome (dashboard
 * card vs. auth-card visual language) and what happens after a successful
 * confirm differ between the two call sites.
 */
export function useTwoFactorSetup() {
  const [step, setStep] = createSignal<"idle" | "settingUp">("idle");
  const [secret, setSecret] = createSignal("");
  const [qrDataUrl, setQrDataUrl] = createSignal("");
  const [confirmCode, setConfirmCode] = createSignal("");
  const [submitting, setSubmitting] = createSignal(false);
  const [errorCode, setErrorCode] = createSignal<ApiErrorCode | null>(null);

  const startSetup = async () => {
    setSubmitting(true);
    setErrorCode(null);
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

  const confirmSetup = async (event: SubmitEvent, onConfirmed: () => void) => {
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
    onConfirmed();
  };

  return { step, secret, qrDataUrl, confirmCode, setConfirmCode, submitting, errorCode, startSetup, cancelSetup, confirmSetup };
}
