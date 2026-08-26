import { createEffect, createSignal, on, onMount, Show, type Component, type JSX } from "solid-js";
import { Transition } from "solid-transition-group";
import { LogIn, UserPlus } from "lucide-solid";
import { SmokeBackground } from "@/features/auth/SmokeBackground";
import { AccountSwitcher } from "@/features/auth/AccountSwitcher";
import { useTwoFactorSetup } from "@/features/auth/useTwoFactorSetup";
import { Logo } from "@/components/common/Logo";
import { Tabs, TabsList, TabsTrigger, TabsContent, TabsIndicator } from "@/components/ui/Tabs";
import { Button } from "@/components/ui/Button";
import { TextField, TextFieldInput, TextFieldLabel } from "@/components/ui/TextField";
import { Checkbox, CheckboxLabel } from "@/components/ui/Checkbox";
import { authStore } from "@/stores/auth.store";
import { mta } from "@/lib/mta/MtaBridge";
import type { RememberedAccount } from "@/types/account";
import { t } from "@/i18n";
import { cn } from "@/lib/cn";

// Visually ported from an earlier project's amethyst-uii (Vue/reka-ui) design, rebuilt on
// SolidJS + Kobalte. No Discord OAuth here - that was specific to the old project.
const TAB_ORDER = ["login", "register"];

type AuthView =
  | { mode: "switcher" }
  | { mode: "form"; prefillLogin?: string; prefillPassword?: string }
  | { mode: "secureAccount" };

/**
 * Login screen root - a single centered card (logo on top) over a
 * full-bleed SmokeBackground, matching the Steam-style account-switcher
 * reference the user provided. Replaces the old two-pane layout
 * (left: form, right: MarqueeGrid) entirely - MarqueeGrid is no longer
 * used anywhere.
 *
 * The card's content is a small router between three views: the account
 * switcher (default once at least one account is remembered locally -
 * see CredentialStore.lua), the login/register form, and the
 * post-registration "secure your account" 2FA step (formerly its own
 * full-screen component, SecureAccountStep.tsx - now folded into this
 * same card so registering never leaves this one window, see the
 * `authStore.phase()` effect below). All three cross-fade with an
 * animated resize (see AnimatedStage) instead of hard-cutting between
 * differently-shaped screens.
 */
export const AuthCard: Component = () => {
  const [accounts, setAccounts] = createSignal<RememberedAccount[]>([]);
  const [accountsLoaded, setAccountsLoaded] = createSignal(false);
  const [view, setView] = createSignal<AuthView>({ mode: "switcher" });

  const refreshAccounts = async () => {
    const list = await mta.listAccounts();
    setAccounts(list);
    return list;
  };

  onMount(async () => {
    const list = await refreshAccounts();
    setAccountsLoaded(true);
    if (list.length === 0) {
      setView({ mode: "form" });
    }
  });

  // Registration moves authStore straight into "securingAccount" (see
  // auth.store.ts's own register()) - this card is still mounted the
  // whole time (App.tsx's <Match> renders LoginView, i.e. this
  // component, for BOTH "unauthenticated" and "securingAccount" now),
  // so the phase transition just needs to swap the local view instead of
  // App.tsx swapping in an entirely different full-screen component.
  createEffect(() => {
    if (authStore.phase() === "securingAccount") {
      setView({ mode: "secureAccount" });
    }
  });

  const loginWithSavedAccount = async (account: RememberedAccount) => {
    if (account.password === undefined) return;

    const result = await authStore.login(account.login, account.password);
    if (result === "success") {
      mta.touchAccount(account.login);
      await refreshAccounts();
      return;
    }
    if (result === "twoFactorRequired") {
      // Reuses the existing 2FA step inside LoginForm rather than a second
      // 2FA UI - hands off the already-known login+password so the form
      // doesn't need the player to retype anything.
      setView({ mode: "form", prefillLogin: account.login, prefillPassword: account.password });
    }
  };

  return (
    <div class="auth-panel relative flex h-full w-full items-center justify-center overflow-hidden font-display">
      {/* No bg-black here (unlike the old two-pane layout) and
          transparent on SmokeBackground below - body's own
          background-color: transparent (globals.css) means this whole
          screen now shows the game world underneath instead of a flat
          black canvas, once a world-space camera flythrough is running
          behind it (see core_auth/client/LoginCamera.lua). */}
      <SmokeBackground color="#ffffff" opacity={0.2} enableWind enableTurbulence transparent />

      <div class="relative z-10 flex w-full max-w-md flex-col gap-8 px-4 py-10">
        <Logo markHeightClass="h-8" wordmarkHeightClass="h-5" class="mx-auto" />

        {/* Nothing renders until the initial account list load settles -
            avoids a one-frame flash of the (usually empty) form before
            onMount's own setView({mode:"form"}) fallback would kick in
            for a fresh install. */}
        <Show when={accountsLoaded()}>
          <AnimatedStage>
            {(() => {
              const current = view();
              if (current.mode === "switcher") {
                return (
                  <AccountSwitcher
                    accounts={accounts()}
                    onSelectSaved={loginWithSavedAccount}
                    onSelectRecent={(account) => setView({ mode: "form", prefillLogin: account.login })}
                    onRemove={async (login) => {
                      mta.removeAccount(login);
                      await refreshAccounts();
                    }}
                    onAddNew={() => setView({ mode: "form" })}
                  />
                );
              }
              if (current.mode === "secureAccount") {
                return <SecureAccountStep />;
              }
              return (
                <AuthFormPanel
                  view={current}
                  canGoBack={accounts().length > 0}
                  onBack={() => setView({ mode: "switcher" })}
                  onAuthenticated={refreshAccounts}
                />
              );
            })()}
          </AnimatedStage>
        </Show>
      </div>
    </div>
  );
};

/**
 * Cross-fades its child (mode="outin" - the leaving view fully unmounts
 * before the entering one mounts, see globals.css's own
 * .auth-card__stage-enter/exit-* comment) AND smoothly resizes the
 * shared stage element to the entering child's own measured height, via
 * the exact same ResizeObserver + explicit inline `height` technique
 * AuthFormPanel already uses one level down for its login<->register
 * tabs (.auth-panel__viewport) - kept as a separate, reusable wrapper
 * here since this stage swaps between three STRUCTURALLY different
 * views (list vs. form vs. QR step), not just two same-shaped tab panels.
 */
const AnimatedStage: Component<{ children: JSX.Element }> = (props) => {
  const [height, setHeight] = createSignal<number>();
  let contentRef: HTMLDivElement | undefined;

  const measure = () => {
    if (contentRef) setHeight(contentRef.offsetHeight);
  };

  createEffect(() => {
    // Tracks props.children so this effect re-runs (and re-observes) on
    // every view swap - contentRef itself is a NEW element each time
    // (mode="outin" unmounts the old one entirely), so the previous
    // ResizeObserver would otherwise keep watching a detached node.
    void props.children;
    queueMicrotask(measure);

    if (!contentRef) return;
    const observer = new ResizeObserver(measure);
    observer.observe(contentRef);
    return () => observer.disconnect();
  });

  return (
    <div class="auth-card__stage" style={{ height: height() !== undefined ? `${height()}px` : undefined }}>
      <Transition
        enterActiveClass="auth-card__stage-enter-active"
        exitActiveClass="auth-card__stage-exit-active"
        enterClass="auth-card__stage-enter-from"
        exitToClass="auth-card__stage-exit-to"
      >
        <div ref={contentRef}>{props.children}</div>
      </Transition>
    </div>
  );
};

/**
 * Post-registration "secure your account" step - shown once, right after
 * a successful registration, before the player can proceed to
 * spawn-select. Was previously its own full-screen component
 * (App.tsx swapped it in directly for authStore.phase() ===
 * "securingAccount") - now just another AuthView inside this same card
 * (see the createEffect above), so registering never leaves this one
 * window. Offers to configure TOTP 2FA (reusing the same enable->confirm
 * proof-of-possession flow as the dashboard's TwoFactorSection.tsx, via
 * the shared useTwoFactorSetup hook) or skip entirely - either path
 * finishes via authStore.finishSecuringAccount(), which never itself
 * calls any account.* endpoint, it only flips the local phase forward
 * (App.tsx's own <Match> then moves on to spawn-select).
 */
const SecureAccountStep: Component = () => {
  const { step, secret, qrDataUrl, confirmCode, setConfirmCode, submitting, errorCode, startSetup, cancelSetup, confirmSetup } = useTwoFactorSetup();

  const errorMessage = () => {
    const code = errorCode();
    return code ? t()(`auth.error.${code}`) : null;
  };

  const handleConfirm = (event: SubmitEvent) => confirmSetup(event, () => authStore.finishSecuringAccount());

  const handleSkip = () => authStore.finishSecuringAccount();

  return (
    <div class="flex flex-col gap-6">
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
  );
};

const submitButtonClass = "auth-panel__submit mt-2 h-auto w-full py-4 font-mono text-xs font-bold uppercase tracking-widest";

interface AuthFormPanelProps {
  view: Extract<AuthView, { mode: "form" }>;
  canGoBack: boolean;
  onBack: () => void;
  onAuthenticated: () => void;
}

const AuthFormPanel: Component<AuthFormPanelProps> = (props) => {
  const [tab, setTab] = createSignal("login");
  const [direction, setDirection] = createSignal<"left" | "right">("right");
  const [viewportHeight, setViewportHeight] = createSignal<number>();

  let loginRef: HTMLDivElement | undefined;
  let registerRef: HTMLDivElement | undefined;

  const handleTabChange = (next: string) => {
    const from = TAB_ORDER.indexOf(tab());
    const to = TAB_ORDER.indexOf(next);
    setDirection(to > from ? "right" : "left");
    setTab(next);
  };

  const measureActivePanel = () => {
    const activeEl = tab() === "login" ? loginRef : registerRef;
    if (activeEl) setViewportHeight(activeEl.offsetHeight);
  };

  onMount(measureActivePanel);
  // ResizeObserver covers both tab switches and error-message height changes without
  // each form needing to report its own height back up.
  createEffect(
    on(tab, () => {
      measureActivePanel();

      const activeEl = tab() === "login" ? loginRef : registerRef;
      if (!activeEl) return;

      const observer = new ResizeObserver(() => measureActivePanel());
      observer.observe(activeEl);
      return () => observer.disconnect();
    }),
  );

  return (
    <div class="flex flex-col gap-4">
      <Show when={props.canGoBack}>
        <Button type="button" variant="link" onClick={props.onBack} class="h-auto w-fit p-0 text-sm text-muted-foreground">
          {t()("auth.switcher.backToSwitcher")}
        </Button>
      </Show>

      <Tabs value={tab()} onChange={handleTabChange}>
        <TabsList class="relative mb-2 h-auto justify-start gap-8 bg-transparent p-0">
          <TabsTrigger
            value="login"
            class="auth-panel__tab relative flex items-center gap-1.5 rounded-none bg-transparent py-2 font-mono text-xs font-bold uppercase tracking-widest text-muted shadow-none transition-colors duration-fast ease-out data-selected:bg-transparent data-selected:text-foreground data-selected:shadow-none"
          >
            <LogIn size={14} />
            {t()("auth.tabs.login")}
          </TabsTrigger>
          <TabsTrigger
            value="register"
            class="auth-panel__tab relative flex items-center gap-1.5 rounded-none bg-transparent py-2 font-mono text-xs font-bold uppercase tracking-widest text-muted shadow-none transition-colors duration-fast ease-out data-selected:bg-transparent data-selected:text-foreground data-selected:shadow-none"
          >
            <UserPlus size={14} />
            {t()("auth.tabs.register")}
          </TabsTrigger>
          <TabsIndicator class="h-0.5 rounded-full bg-gradient-to-r from-accent-indigo to-accent-violet" />
        </TabsList>

        <div
          class={cn("auth-panel__viewport relative", direction() === "right" ? "auth-panel__slide-right" : "auth-panel__slide-left")}
          style={{ height: viewportHeight() !== undefined ? `${viewportHeight()}px` : undefined }}
        >
          <TabsContent ref={loginRef} value="login" forceMount class="auth-panel__content flex flex-col gap-6">
            <LoginForm prefillLogin={props.view.prefillLogin} prefillPassword={props.view.prefillPassword} onAuthenticated={props.onAuthenticated} />
          </TabsContent>

          <TabsContent ref={registerRef} value="register" forceMount class="auth-panel__content flex flex-col gap-6">
            <RegisterForm onSwitchToLogin={() => handleTabChange("login")} />
          </TabsContent>
        </div>
      </Tabs>
    </div>
  );
};

interface LoginFormProps {
  prefillLogin?: string;
  prefillPassword?: string;
  onAuthenticated: () => void;
}

const LoginForm: Component<LoginFormProps> = (props) => {
  const [login, setLogin] = createSignal(props.prefillLogin ?? "");
  const [password, setPassword] = createSignal(props.prefillPassword ?? "");
  const [rememberMe, setRememberMe] = createSignal(false);
  const [submitting, setSubmitting] = createSignal(false);
  const [twoFactorPending, setTwoFactorPending] = createSignal(false);
  const [twoFactorCode, setTwoFactorCode] = createSignal("");
  const [trustDevice, setTrustDevice] = createSignal(false);

  const errorMessage = () => {
    const code = authStore.lastError();
    if (!code) return null;
    return t()(`auth.error.${code}`);
  };

  // Always upserts (never save-else-clear) - upsertAccount itself encodes
  // "saved" vs "recently used" via rememberPassword, and re-entering a
  // password for a recently-used account should not silently upgrade it
  // to "saved" without the checkbox being explicitly checked again
  // (rememberMe defaults to false in every path, including prefilled ones).
  const persistAccount = (trimmedLogin: string, currentPassword: string) => {
    mta.upsertAccount(trimmedLogin, currentPassword, rememberMe());
    props.onAuthenticated();
  };

  const handleSubmit = async (event: SubmitEvent) => {
    event.preventDefault();
    if (submitting()) return;

    const trimmedLogin = login().trim();
    const currentPassword = password();

    setSubmitting(true);
    const result = await authStore.login(trimmedLogin, currentPassword);
    setSubmitting(false);

    if (result === "twoFactorRequired") {
      setTwoFactorPending(true);
      return;
    }
    if (result !== "success") return;

    persistAccount(trimmedLogin, currentPassword);
  };

  const handleTwoFactorSubmit = async (event: SubmitEvent) => {
    event.preventDefault();
    if (submitting()) return;

    setSubmitting(true);
    const ok = await authStore.verifyTwoFactor(twoFactorCode().trim(), trustDevice());
    setSubmitting(false);

    if (!ok) {
      // Retryable in place - the server-side pending login isn't consumed
      // by a wrong code, only by success or its own TTL/rate limit. Clear
      // the input for a fresh attempt rather than bouncing back to the
      // password step.
      setTwoFactorCode("");
      return;
    }

    persistAccount(login().trim(), password());
  };

  const backToPassword = () => {
    setTwoFactorPending(false);
    setTwoFactorCode("");
    setTrustDevice(false);
  };

  return (
    <Show
      when={!twoFactorPending()}
      fallback={
        <TwoFactorStepForm
          code={twoFactorCode()}
          onCodeChange={setTwoFactorCode}
          trustDevice={trustDevice()}
          onTrustDeviceChange={setTrustDevice}
          onSubmit={handleTwoFactorSubmit}
          onBack={backToPassword}
          submitting={submitting()}
          errorMessage={errorMessage()}
        />
      }
    >
      <div class="text-center">
        <h1 class="text-2xl font-bold tracking-tight text-foreground">{t()("auth.login.title")}</h1>
        <p class="mt-1 text-sm text-muted-foreground">{t()("auth.login.subtitle")}</p>
      </div>

      <form class="flex flex-col gap-4" onSubmit={handleSubmit}>
        <AuthField
          id="auth-login"
          label={t()("auth.login.login")}
          placeholder={t()("auth.login.loginPlaceholder")}
          value={login()}
          onInput={setLogin}
          minLength={3}
        />

        <AuthField
          id="auth-password"
          type="password"
          label={t()("auth.login.password")}
          placeholder={t()("auth.login.passwordPlaceholder")}
          value={password()}
          onInput={setPassword}
          minLength={8}
        />

        <Checkbox checked={rememberMe()} onChange={setRememberMe} variant="gradient" class="mx-auto w-fit">
          <CheckboxLabel class="cursor-pointer select-none text-sm text-muted-foreground">
            {t()("auth.login.rememberMe")}
          </CheckboxLabel>
        </Checkbox>

        <Show when={errorMessage()}>
          <p class="text-sm text-danger">{errorMessage()}</p>
        </Show>

        <Button
          type="submit"
          variant="gradient"
          class={submitButtonClass}
          loading={submitting()}
          disabled={submitting() || !login() || !password()}
        >
          {submitting() ? t()("auth.login.submitting") : t()("auth.login.submit")}
        </Button>
      </form>
    </Show>
  );
};

interface TwoFactorStepFormProps {
  code: string;
  onCodeChange: (value: string) => void;
  trustDevice: boolean;
  onTrustDeviceChange: (value: boolean) => void;
  onSubmit: (event: SubmitEvent) => void;
  onBack: () => void;
  submitting: boolean;
  errorMessage: string | null;
}

const TwoFactorStepForm: Component<TwoFactorStepFormProps> = (props) => {
  return (
    <>
      <div class="text-center">
        <h1 class="text-2xl font-bold tracking-tight text-foreground">{t()("auth.twoFactor.title")}</h1>
        <p class="mt-1 text-sm text-muted-foreground">{t()("auth.twoFactor.subtitle")}</p>
      </div>

      <form class="flex flex-col gap-4" onSubmit={props.onSubmit}>
        <TextField value={props.code} onChange={props.onCodeChange} class="gap-2">
          <TextFieldLabel for="auth-two-factor-code" class="select-none font-mono text-2xs font-bold uppercase tracking-widest text-accent-indigo/70">
            {t()("auth.twoFactor.codeLabel")}
          </TextFieldLabel>
          <TextFieldInput
            id="auth-two-factor-code"
            name="auth-two-factor-code"
            type="text"
            inputmode="numeric"
            pattern="[0-9]*"
            autocomplete="one-time-code"
            placeholder={t()("auth.twoFactor.codePlaceholder")}
            maxLength={6}
            autofocus
            class="h-auto border-accent-indigo/20 bg-black/60 px-4 py-3.5 backdrop-blur-md focus-visible:outline-none focus-visible:ring-0 focus-visible:ring-offset-0 focus-visible:border-accent-indigo/60"
          />
        </TextField>

        <Checkbox checked={props.trustDevice} onChange={props.onTrustDeviceChange} variant="gradient" class="mx-auto w-fit">
          <CheckboxLabel class="cursor-pointer select-none text-sm text-muted-foreground">
            {t()("auth.twoFactor.trustDevice")}
          </CheckboxLabel>
        </Checkbox>

        <Show when={props.errorMessage}>
          <p class="text-sm text-danger">{props.errorMessage}</p>
        </Show>

        <Button
          type="submit"
          variant="gradient"
          class={submitButtonClass}
          loading={props.submitting}
          disabled={props.submitting || props.code.length !== 6}
        >
          {props.submitting ? t()("auth.login.submitting") : t()("auth.twoFactor.submit")}
        </Button>

        <Button type="button" variant="ghost" onClick={props.onBack} disabled={props.submitting}>
          {t()("auth.twoFactor.back")}
        </Button>
      </form>
    </>
  );
};

const RegisterForm: Component<{ onSwitchToLogin: () => void }> = (props) => {
  const [login, setLogin] = createSignal("");
  const [email, setEmail] = createSignal("");
  const [password, setPassword] = createSignal("");
  const [confirmPassword, setConfirmPassword] = createSignal("");
  const [submitting, setSubmitting] = createSignal(false);
  const [mismatch, setMismatch] = createSignal(false);

  const errorMessage = () => {
    if (mismatch()) return t()("auth.register.passwordMismatch");
    const code = authStore.lastError();
    if (!code) return null;
    return t()(`auth.error.${code}`);
  };

  const handleSubmit = async (event: SubmitEvent) => {
    event.preventDefault();
    if (submitting()) return;

    if (password() !== confirmPassword()) {
      setMismatch(true);
      return;
    }
    setMismatch(false);

    setSubmitting(true);
    const success = await authStore.register(login().trim(), email().trim(), password());
    setSubmitting(false);

    if (success) {
      mta.notify("onClientShowNotification", "success", t()("account.created.description"), {
        title: t()("account.created"),
      });
      props.onSwitchToLogin();
    }
  };

  return (
    <>
      <div class="text-center">
        <h1 class="text-2xl font-bold tracking-tight text-foreground">{t()("auth.register.title")}</h1>
        <p class="mt-1 text-sm text-muted-foreground">{t()("auth.register.subtitle")}</p>
      </div>

      <form class="flex flex-col gap-4" onSubmit={handleSubmit}>
        <AuthField
          id="auth-register-login"
          label={t()("auth.login.login")}
          placeholder={t()("auth.login.loginPlaceholder")}
          value={login()}
          onInput={setLogin}
          minLength={3}
          maxLength={24}
        />

        <AuthField
          id="auth-register-email"
          type="email"
          label={t()("auth.login.email")}
          placeholder={t()("auth.login.emailPlaceholder")}
          value={email()}
          onInput={setEmail}
        />

        <AuthField
          id="auth-register-password"
          type="password"
          label={t()("auth.login.password")}
          placeholder={t()("auth.login.passwordPlaceholder")}
          value={password()}
          onInput={setPassword}
          minLength={8}
          maxLength={128}
        />

        <AuthField
          id="auth-register-confirm-password"
          type="password"
          label={t()("auth.register.confirmPassword")}
          placeholder={t()("auth.register.confirmPasswordPlaceholder")}
          value={confirmPassword()}
          onInput={setConfirmPassword}
          minLength={8}
          maxLength={128}
        />

        <Show when={errorMessage()}>
          <p class="text-sm text-danger">{errorMessage()}</p>
        </Show>

        <Button
          type="submit"
          variant="gradient"
          class={submitButtonClass}
          loading={submitting()}
          disabled={submitting() || !login() || !email() || !password() || !confirmPassword()}
        >
          {submitting() ? t()("auth.login.submitting") : t()("auth.register.submit")}
        </Button>
      </form>
    </>
  );
};

interface AuthFieldProps {
  id: string;
  label: string;
  placeholder: string;
  value: string;
  onInput: (value: string) => void;
  type?: string;
  minLength?: number;
  maxLength?: number;
}

const AuthField: Component<AuthFieldProps> = (props) => {
  const isPassword = () => props.type === "password";
  const [reveal, setReveal] = createSignal(false);

  return (
    <TextField value={props.value} onChange={props.onInput} class="gap-2">
      <TextFieldLabel
        for={props.id}
        class="select-none font-mono text-2xs font-bold uppercase tracking-widest text-accent-indigo/70"
      >
        {props.label}
      </TextFieldLabel>
      <div class="relative">
        <TextFieldInput
          id={props.id}
          name={props.id}
          type={isPassword() && reveal() ? "text" : ((props.type as "text" | "email" | "password" | undefined) ?? "text")}
          autocomplete="off"
          placeholder={props.placeholder}
          minLength={props.minLength}
          maxLength={props.maxLength}
          required
          class={cn(
            "h-auto border-accent-indigo/20 bg-black/60 px-4 py-3.5 backdrop-blur-md",
            "focus-visible:outline-none focus-visible:ring-0 focus-visible:ring-offset-0 focus-visible:border-accent-indigo/60",
            isPassword() && "pr-11",
          )}
        />
        <Show when={isPassword()}>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={() => setReveal((current) => !current)}
            aria-label={reveal() ? t()("auth.password.hide") : t()("auth.password.show")}
            class="absolute right-1 top-1/2 h-8 w-8 -translate-y-1/2 text-muted hover:bg-accent-indigo/10 hover:text-foreground"
          >
            <Show
              when={reveal()}
              fallback={
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                  <circle cx="12" cy="12" r="3" />
                </svg>
              }
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
                <line x1="1" y1="1" x2="23" y2="23" />
              </svg>
            </Show>
          </Button>
        </Show>
      </div>
    </TextField>
  );
};
