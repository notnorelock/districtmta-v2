import type { JSX, ValidComponent } from "solid-js";
import { splitProps } from "solid-js";

import * as ButtonPrimitive from "@kobalte/core/button";
import type { PolymorphicProps } from "@kobalte/core/polymorphic";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/cn";

// Ported from solid-ui (github.com/stefan-karger/solid-ui) by hand, not via its CLI,
// which scaffolds Tailwind v3 config and would overwrite this project's v4 @theme setup.
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        outline: "border border-input hover:bg-accent hover:text-accent-foreground",
        secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline",
        // hover:bg-transparent is deliberate: the gradient is the resting state, hover
        // only shifts bg-position/shadow, not a separate background color.
        gradient:
          "border border-accent-indigo/40 bg-gradient-to-r from-accent-indigo via-accent-violet to-accent-indigo bg-size-[200%_100%] text-white shadow-[0_8px_30px_rgba(99,102,241,0.35)] transition-[background-position,box-shadow] hover:bg-transparent hover:bg-right hover:shadow-[0_12px_40px_rgba(99,102,241,0.5)] focus-visible:ring-accent-indigo/50",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-9 px-3 text-xs",
        lg: "h-11 px-8",
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
