import type { Component, ComponentProps } from "solid-js";
import { splitProps } from "solid-js";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/cn";

// New for the design-system pass (docs/DesignSystem.md). Replaces
// ad-hoc per-feature status chips - ScoreboardOverlay's own .count pill,
// .dotPending/.dotReady status dots, GroupPanelOverlay's .groupTabDot -
// with one shared component. Sharp/square by default (no rounded-full)
// per the terminal-tile direction already established by DutyIndicator's
// own .icon square-tile-plus-color convention - a `dot` size variant is
// kept for cases that specifically need the small circular indicator
// shape (status dots), rather than treating square as the only option.
const badgeVariants = cva(
  "inline-flex shrink-0 items-center gap-1 border font-mono text-2xs font-medium uppercase tracking-wide transition-colors duration-fast ease-out",
  {
    variants: {
      variant: {
        default: "border-border bg-secondary text-secondary-foreground",
        primary: "border-primary/40 bg-primary/10 text-primary",
        success: "border-success/40 bg-success/10 text-success",
        warning: "border-warning/40 bg-warning/10 text-warning",
        danger: "border-danger/40 bg-danger/10 text-danger",
        muted: "border-border bg-transparent text-muted-foreground",
      },
      size: {
        default: "px-1.5 py-0.5",
        sm: "px-1 py-px text-[10px]",
        dot: "size-1.5 rounded-full border-0 p-0",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

type BadgeProps = ComponentProps<"span"> & VariantProps<typeof badgeVariants>;

const Badge: Component<BadgeProps> = (props) => {
  const [local, others] = splitProps(props, ["class", "variant", "size"]);
  return <span class={cn(badgeVariants({ variant: local.variant, size: local.size }), local.class)} {...others} />;
};

export { Badge, badgeVariants };
export type { BadgeProps };
