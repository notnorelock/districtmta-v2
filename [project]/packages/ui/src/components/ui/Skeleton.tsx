import type { Component, ComponentProps } from "solid-js";
import { splitProps } from "solid-js";

import { cn } from "@/lib/cn";

// New for the design-system pass (docs/DesignSystem.md). Addresses the
// "static/stiff" complaint directly - the only loading affordance
// anywhere before this was animate-spin spinners (Button, SpawnSelectView,
// ResourceCheckScreen, LoadingScreen); this gives data-heavy content
// (an eventual Table full of rows, e.g.) a way to show loading state
// without a blank flash while data streams in. Plain opacity pulse
// (animate-pulse is Tailwind's own built-in keyframe, unrelated to this
// session's --transition-duration-*/--ease-* tokens, which only apply
// to `transition`, not `animation`). Sharp corners, no radius - matches
// every other primitive's radius-0 default.
const Skeleton: Component<ComponentProps<"div">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);
  return <div class={cn("animate-pulse bg-secondary", local.class)} {...others} />;
};

export { Skeleton };
