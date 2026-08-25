import type { Component, ComponentProps } from "solid-js";
import { splitProps } from "solid-js";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/cn";

// New for the design-system pass (docs/DesignSystem.md). Replaces
// ad-hoc div-pair patterns like DashboardOverlay's own .levelBar/
// .levelBarFill. Not Kobalte-backed (no Progress primitive in Kobalte
// as of this project's version) - a plain track+fill div pair with the
// fill width driven by an inline style, same technique the dashboard
// already used, formalized as a shared component. Sharp corners by
// default (no rounded-full) matching the radius-0 direction.
const progressTrackVariants = cva("w-full overflow-hidden bg-secondary", {
  variants: {
    size: {
      default: "h-1.5",
      sm: "h-1",
      lg: "h-2.5",
    },
  },
  defaultVariants: { size: "default" },
});

const progressFillVariants = cva("h-full transition-[width] duration-base ease-out", {
  variants: {
    variant: {
      default: "bg-primary",
      success: "bg-success",
      warning: "bg-warning",
      danger: "bg-danger",
    },
  },
  defaultVariants: { variant: "default" },
});

type ProgressProps = ComponentProps<"div"> &
  VariantProps<typeof progressTrackVariants> &
  VariantProps<typeof progressFillVariants> & {
    /** 0-100. Not clamped internally - pass a pre-clamped value. */
    value: number;
  };

const Progress: Component<ProgressProps> = (props) => {
  const [local, others] = splitProps(props, ["class", "size", "variant", "value"]);
  return (
    <div
      role="progressbar"
      aria-valuenow={local.value}
      aria-valuemin={0}
      aria-valuemax={100}
      class={cn(progressTrackVariants({ size: local.size }), local.class)}
      {...others}
    >
      <div class={progressFillVariants({ variant: local.variant })} style={{ width: `${local.value}%` }} />
    </div>
  );
};

export { Progress };
export type { ProgressProps };
