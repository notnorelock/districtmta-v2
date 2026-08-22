import { createEffect, createSignal, on, onMount, Show, type Component } from "solid-js";
import { SmokeBackground } from "@/features/auth/SmokeBackground";
import { MarqueeGrid } from "@/features/auth/MarqueeGrid";
import { Tabs, TabsList, TabsTrigger, TabsContent, TabsIndicator } from "@/components/ui/Tabs";
import { Button } from "@/components/ui/Button";
import { TextField, TextFieldInput, TextFieldLabel } from "@/components/ui/TextField";
import { Checkbox, CheckboxLabel } from "@/components/ui/Checkbox";
import { authStore } from "@/stores/auth.store";
import { mta } from "@/lib/mta/MtaBridge";
import { t } from "@/i18n";
import { cn } from "@/lib/cn";

// Visually ported from an earlier project's amethyst-uii (Vue/reka-ui) design, rebuilt on
// SolidJS + Kobalte. No Discord OAuth here - that was specific to the old project.
const TAB_ORDER = ["login", "register"];

export const AuthCard: Component = () => {
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
    <div class="auth-panel relative flex h-full w-full overflow-hidden bg-black font-display">
      <div class="relative flex w-full max-w-md flex-col justify-center gap-10 bg-black px-12 py-10 md:w-2/5">
        <SmokeBackground color="#ffffff" opacity={0.25} enableWind enableTurbulence />

        <div class="relative z-10 flex flex-col gap-10">
          <Tabs value={tab()} onChange={handleTabChange}>
            <TabsList class="relative mb-2 h-auto justify-start gap-8 bg-transparent p-0">
              <TabsTrigger
                value="login"
                class="auth-panel__tab relative rounded-none bg-transparent py-2 text-xs font-bold uppercase tracking-widest text-muted shadow-none transition-colors data-selected:bg-transparent data-selected:text-foreground data-selected:shadow-none"
              >
                {t()("auth.tabs.login")}
              </TabsTrigger>
              <TabsTrigger
                value="register"
                class="auth-panel__tab relative rounded-none bg-transparent py-2 text-xs font-bold uppercase tracking-widest text-muted shadow-none transition-colors data-selected:bg-transparent data-selected:text-foreground data-selected:shadow-none"
              >
                {t()("auth.tabs.register")}
              </TabsTrigger>
              <TabsIndicator class="h-0.5 rounded-full bg-gradient-to-r from-accent-indigo to-accent-violet" />
            </TabsList>

            <div
              class={cn("auth-panel__viewport relative", direction() === "right" ? "auth-panel__slide-right" : "auth-panel__slide-left")}
              style={{ height: viewportHeight() !== undefined ? `${viewportHeight()}px` : undefined }}
            >
              <TabsContent ref={loginRef} value="login" forceMount class="auth-panel__content flex flex-col gap-6">
                <LoginForm />
              </TabsContent>

              <TabsContent ref={registerRef} value="register" forceMount class="auth-panel__content flex flex-col gap-6">
                <RegisterForm onSwitchToLogin={() => handleTabChange("login")} />
              </TabsContent>
            </div>
          </Tabs>
        </div>
      </div>

      <div class="relative hidden flex-1 overflow-hidden bg-black md:block">
        <MarqueeGrid />
      </div>
    </div>
  );
};

const submitButtonClass = "auth-panel__submit mt-2 h-auto w-full rounded-xl py-4 text-xs font-bold uppercase tracking-widest";

const LoginForm: Component = () => {
  const [login, setLogin] = createSignal("");
  const [password, setPassword] = createSignal("");
  const [rememberMe, setRememberMe] = createSignal(false);
  const [submitting, setSubmitting] = createSignal(false);

  // Pure UX convenience - the password is still submitted and verified fresh server-side.
  onMount(async () => {
    const saved = await mta.loadCredentials();
    if (saved) {
      setLogin(saved.login);
      setPassword(saved.password);
      setRememberMe(true);
    }
  });

  const errorMessage = () => {
    const code = authStore.lastError();
    if (!code) return null;
    return t()(`auth.error.${code}`);
  };

  const handleSubmit = async (event: SubmitEvent) => {
    event.preventDefault();
    if (submitting()) return;

    const trimmedLogin = login().trim();
    const currentPassword = password();

    setSubmitting(true);
    const success = await authStore.login(trimmedLogin, currentPassword);
    setSubmitting(false);

    if (!success) return;

    if (rememberMe()) {
      mta.saveCredentials(trimmedLogin, currentPassword);
    } else {
      mta.clearCredentials();
    }
  };

  return (
    <>
      <div>
        <h1 class="text-2xl font-bold uppercase tracking-wide text-foreground">{t()("auth.login.title")}</h1>
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

        <Checkbox checked={rememberMe()} onChange={setRememberMe} variant="gradient">
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
      <div>
        <h1 class="text-2xl font-bold uppercase tracking-wide text-foreground">{t()("auth.register.title")}</h1>
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
        class="select-none font-mono text-xs font-bold uppercase tracking-widest text-accent-indigo/70"
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
            "h-auto rounded-xl border-accent-indigo/20 bg-black/60 px-4 py-3.5 backdrop-blur-md",
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
            class="absolute right-1 top-1/2 h-8 w-8 -translate-y-1/2 rounded-lg text-muted hover:bg-accent-indigo/10 hover:text-foreground"
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
