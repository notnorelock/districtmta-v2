import { type Component, For, Show, createMemo, createSignal } from "solid-js";
import { User, X } from "lucide-solid";
import { Button } from "@/components/ui/Button";
import { badgeVariants } from "@/components/ui/Badge";
import type { RememberedAccount } from "@/types/account";
import { t } from "@/i18n";
import { cn } from "@/lib/cn";

export interface AccountSwitcherProps {
  accounts: RememberedAccount[];
  onSelectSaved: (account: RememberedAccount) => void;
  onSelectRecent: (account: RememberedAccount) => void;
  onRemove: (login: string) => void;
  onAddNew: () => void;
}

/**
 * Steam-style account switcher shown on the login screen when at least
 * one account is remembered locally (see CredentialStore.lua /
 * AuthCard.tsx, which falls straight to the login/register form
 * otherwise). Two sections - "saved" (password remembered, one-click
 * login) and "recently used" (login only, password re-entry required) -
 * derived purely from whether an entry carries a password, plus an
 * "add new account" row that hands off to the form.
 */
export const AccountSwitcher: Component<AccountSwitcherProps> = (props) => {
  const savedAccounts = createMemo(() =>
    props.accounts.filter((account) => account.password !== undefined).sort((a, b) => b.lastUsedAt - a.lastUsedAt),
  );
  const recentAccounts = createMemo(() =>
    props.accounts.filter((account) => account.password === undefined).sort((a, b) => b.lastUsedAt - a.lastUsedAt),
  );

  return (
    <div class="flex flex-col gap-6">
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-foreground">{t()("auth.switcher.title")}</h1>
      </div>

      <Show when={savedAccounts().length > 0}>
        <div class="flex flex-col gap-2">
          <div class="flex items-baseline justify-between gap-2">
            <span class="font-mono text-2xs font-bold uppercase tracking-widest text-accent-indigo/70">
              {t()("auth.switcher.savedHeading")}
            </span>
          </div>
          <p class="text-xs text-muted-foreground">{t()("auth.switcher.savedCaption")}</p>

          <div class="flex flex-col gap-2">
            <For each={savedAccounts()}>
              {(account) => (
                <AccountRow
                  account={account}
                  isSaved
                  onSelect={() => props.onSelectSaved(account)}
                  onRemove={() => props.onRemove(account.login)}
                />
              )}
            </For>
          </div>
        </div>
      </Show>

      <Show when={recentAccounts().length > 0}>
        <div class="flex flex-col gap-2">
          <div class="flex items-baseline justify-between gap-2">
            <span class="font-mono text-2xs font-bold uppercase tracking-widest text-accent-indigo/70">
              {t()("auth.switcher.recentHeading")}
            </span>
            <span class="font-mono text-2xs uppercase tracking-wide text-muted-foreground">{t()("auth.switcher.recentHint")}</span>
          </div>

          <div class="flex flex-col gap-2">
            <For each={recentAccounts()}>
              {(account) => (
                <AccountRow
                  account={account}
                  isSaved={false}
                  onSelect={() => props.onSelectRecent(account)}
                  onRemove={() => props.onRemove(account.login)}
                />
              )}
            </For>
          </div>
        </div>
      </Show>

      <button
        type="button"
        onClick={props.onAddNew}
        class="flex items-center gap-3 border border-dashed border-border px-4 py-3 text-left transition-colors duration-fast ease-out hover:border-accent-indigo/40 hover:bg-accent-indigo/5"
      >
        <span class="flex size-10 shrink-0 items-center justify-center border border-dashed border-border text-lg text-muted-foreground">+</span>
        <span class="flex min-w-0 flex-col">
          <span class="text-sm font-semibold text-foreground">{t()("auth.switcher.addNew")}</span>
          <span class="text-xs text-muted-foreground">{t()("auth.switcher.addNewHint")}</span>
        </span>
      </button>
    </div>
  );
};

interface AccountRowProps {
  account: RememberedAccount;
  isSaved: boolean;
  onSelect: () => void;
  onRemove: () => void;
}

const AccountRow: Component<AccountRowProps> = (props) => {
  const [hovering, setHovering] = createSignal(false);

  return (
    <div
      class="flex items-center gap-3 border border-border px-3 py-2.5"
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      <User />

      <div class="flex min-w-0 flex-1 flex-col">
        <span class="truncate text-sm font-semibold text-foreground">{props.account.login}</span>
        <span class="truncate text-xs text-muted-foreground">
          {props.isSaved ? t()("auth.switcher.statusSaved") : t()("auth.switcher.statusRecent")}
        </span>
      </div>

      {/* The status pill and the "select account" button swap places on
          row hover via mirrored grid-template-columns 0fr<->1fr
          transitions (animates to each element's own intrinsic width
          without knowing it up front, unlike a max-width guess) - the
          pill collapses away to make room instead of the button just
          appending itself alongside it, so only one call-to-action is
          ever visible at a time. */}
      <div
        class="grid overflow-hidden transition-[grid-template-columns] duration-fast ease-out"
        style={{ "grid-template-columns": hovering() ? "1fr" : "0fr" }}
      >
        <div class="min-w-0">
          <Button
            type="button"
            variant="gradient"
            size="sm"
            class="h-7 shrink-0 whitespace-nowrap px-3 text-2xs"
            onClick={props.onSelect}
          >
            {t()("auth.switcher.selectAccount")}
          </Button>
        </div>
      </div>

      <div
        class="grid overflow-hidden transition-[grid-template-columns] duration-fast ease-out"
        style={{ "grid-template-columns": hovering() ? "0fr" : "1fr" }}
      >
        <div class="min-w-0">
          <button
            type="button"
            onClick={props.onSelect}
            class={cn(badgeVariants({ variant: props.isSaved ? "primary" : "muted" }), "shrink-0 cursor-pointer whitespace-nowrap")}
          >
            {props.isSaved ? t()("auth.switcher.pillSaved") : t()("auth.switcher.pillRecent")}
          </button>
        </div>
      </div>

      <Button
        type="button"
        variant="ghost"
        size="icon"
        class="size-8 shrink-0 text-muted hover:bg-danger/10 hover:text-danger"
        aria-label={t()("auth.switcher.removeAccount")}
        onClick={(event: MouseEvent) => {
          event.stopPropagation();
          props.onRemove();
        }}
      >
        <X size={14} />
      </Button>
    </div>
  );
};
