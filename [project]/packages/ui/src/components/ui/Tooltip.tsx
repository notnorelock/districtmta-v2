import type { JSXElement, ValidComponent } from "solid-js";
import { splitProps } from "solid-js";

import type { PolymorphicProps } from "@kobalte/core/polymorphic";
import * as TooltipPrimitive from "@kobalte/core/tooltip";

import { cn } from "@/lib/cn";

/**
 * Ported from solid-ui - see Button.tsx's module comment for context.
 * openDelay/closeDelay default to Kobalte's own (700ms/300ms) unless a
 * caller overrides them - fast enough for a HUD/panel that reads at a
 * glance, not so fast that grazing the mouse across a row of icons spams
 * a tooltip per pixel.
 */
const Tooltip = TooltipPrimitive.Root;
const TooltipTrigger = TooltipPrimitive.Trigger;

type TooltipContentProps<T extends ValidComponent = "div"> = TooltipPrimitive.TooltipContentProps<T> & {
  class?: string | undefined;
};

const TooltipContent = <T extends ValidComponent = "div">(props: PolymorphicProps<T, TooltipContentProps<T>>) => {
  const [local, others] = splitProps(props as TooltipContentProps, ["class"]);
  const children = (props as { children?: JSXElement }).children;
  return (
    <TooltipPrimitive.Portal>
      <TooltipPrimitive.Content
        class={cn(
          // font-display explicitly - Portal teleports this to document.body,
          // outside any panel's own font-display wrapper (InventoryOverlay.
          // module.scss's .panel etc.), so without this it silently fell
          // back to body's own font-sans (Inter) instead of matching every
          // other panel's Titillium Web.
          "z-50 origin-[var(--kb-popper-content-transform-origin)] rounded-md border border-border bg-popover px-2.5 py-1.5 font-display text-xs text-popover-foreground shadow-md data-expanded:animate-in data-closed:animate-out data-closed:fade-out-0 data-expanded:fade-in-0 data-closed:zoom-out-95 data-expanded:zoom-in-95",
          local.class,
        )}
        {...others}
      >
        {children}
        <TooltipPrimitive.Arrow size={12} />
      </TooltipPrimitive.Content>
    </TooltipPrimitive.Portal>
  );
};

export { Tooltip, TooltipTrigger, TooltipContent };
