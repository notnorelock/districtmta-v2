import type { JSX, ValidComponent } from "solid-js";
import { splitProps } from "solid-js";

import * as ButtonPrimitive from "@kobalte/core/button";
import type { PolymorphicProps } from "@kobalte/core/polymorphic";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/cn";

// Ported from solid-ui (github.com/stefan-karger/solid-ui) by hand, not via its CLI,
// which scaffolds Tailwind v3 config and would overwrite this project's v4 @theme setup.
const buttonVariants = cva(
  // "relative" here (a Tailwind utility, not a custom class) is what
  // .button-sweep's own ::before pseudo-element positions against -
  // see that class's own comment in globals.css for why it can't set
  // position:relative itself (a custom class and a Tailwind utility
  // both setting `position` race on CSS source order, not markup
  // order, and previously broke an ABSOLUTELY-POSITIONED CHILD button
  // that also happened to use variant="ghost" - AuthField's
  // password-reveal toggle - by winning that race unpredictably).
  "relative inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-[color,background-color,border-color,transform,box-shadow] duration-fast ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        // button-sweep (globals.css) adds the reference landing page's
        // hover shine-sweep to every surface variant below (all but
        // "link", which has no surface to sweep across) - see that
        // class's own comment.
        default: "button-sweep bg-primary text-primary-foreground hover:bg-primary/90",
        destructive: "button-sweep bg-destructive text-destructive-foreground hover:bg-destructive/90",
        outline: "button-sweep border border-input hover:bg-accent hover:text-accent-foreground",
        secondary: "button-sweep bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost: "button-sweep hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline",
        // hover:bg-transparent is deliberate: the gradient is the resting state, hover
        // only shifts bg-position/shadow, not a separate background color.
        // shadow colors are the literal RGB of --color-accent-indigo
        // (#ffab48) - arbitrary-value shadow-[...] utilities can't
        // reference a CSS custom property's color directly the way
        // bg-accent-indigo etc. can, so this has to be kept in sync by
        // hand if that token's value ever changes again (see
        // styles/globals.css's own token comment).
        gradient:
          "button-sweep border border-accent-indigo/40 bg-gradient-to-r from-accent-indigo via-accent-violet to-accent-indigo bg-size-[200%_100%] text-white shadow-[0_8px_30px_rgba(255,171,72,0.35)] transition-[background-position,box-shadow,transform] hover:bg-transparent hover:bg-right hover:shadow-[0_12px_40px_rgba(255,171,72,0.5)] focus-visible:ring-accent-indigo/50",
      },
      size: {
        // hover:-translate-y-0.5 lift lives per-size (not in the base
        // class) - "icon" is deliberately excluded: those buttons are
        // frequently absolutely-positioned/transform-centered by their
        // OWN call site (e.g. AuthField's password-reveal toggle uses
        // -translate-y-1/2 to vertically center itself), and hover
        // fighting that transform made the button visibly jump/lose its
        // centering on hover instead of gently lifting.
        default: "h-10 px-4 py-2 hover:-translate-y-0.5 disabled:hover:translate-y-0",
        sm: "h-9 px-3 text-xs hover:-translate-y-0.5 disabled:hover:translate-y-0",
        lg: "h-11 px-8 hover:-translate-y-0.5 disabled:hover:translate-y-0",
        icon: "size-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

type ButtonProps<T extends ValidComponent = "button"> = ButtonPrimitive.ButtonRootProps<T> &
  VariantProps<typeof buttonVariants> & {
    class?: string | undefined;
    children?: JSX.Element;
    loading?: boolean;
  };

const Button = <T extends ValidComponent = "button">(props: PolymorphicProps<T, ButtonProps<T>>) => {
  const [local, others] = splitProps(props as ButtonProps, ["variant", "size", "class", "loading", "children", "disabled"]);

  return (
    <ButtonPrimitive.Root
      class={cn(buttonVariants({ variant: local.variant, size: local.size }), local.class)}
      disabled={local.disabled || local.loading}
      {...others}
    >
      {local.loading && (
        <span class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />
      )}
      {local.children}
    </ButtonPrimitive.Root>
  );
};

export { Button, buttonVariants };
export type { ButtonProps };
