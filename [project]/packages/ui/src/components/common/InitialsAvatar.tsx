import type { Component } from "solid-js";
import { cn } from "@/lib/cn";

/**
 * Plain "login -> circle with initials" primitive - shared location
 * (like Logo.tsx) since it's generically reusable, not auth-specific.
 * Deliberately not a components/ui/Avatar.tsx design-system primitive -
 * nothing else in the app needs a generalized avatar today, this is
 * just a div.
 */
export interface InitialsAvatarProps {
  login: string;
  class?: string;
}

export const InitialsAvatar: Component<InitialsAvatarProps> = (props) => {
  const initials = () => props.login.trim().slice(0, 2).toUpperCase();

  return (
    <div
      class={cn(
        "flex size-10 shrink-0 items-center justify-center border border-accent-indigo/40 bg-gradient-to-br from-accent-indigo/20 to-accent-violet/20 font-mono text-xs font-bold uppercase tracking-wide text-foreground",
        props.class,
      )}
    >
      {initials()}
    </div>
  );
};
