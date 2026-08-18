import type { JSX, ValidComponent } from "solid-js";
import { Match, splitProps, Switch } from "solid-js";

import * as CheckboxPrimitive from "@kobalte/core/checkbox";
import type { PolymorphicProps } from "@kobalte/core/polymorphic";

import { cn } from "@/lib/cn";

type CheckboxLabelProps<T extends ValidComponent = "label"> = CheckboxPrimitive.CheckboxLabelProps<T> & {
  class?: string | undefined;
};

const CheckboxLabel = <T extends ValidComponent = "label">(props: PolymorphicProps<T, CheckboxLabelProps<T>>) => {
  const [local, others] = splitProps(props as CheckboxLabelProps, ["class"]);
  return (
    <CheckboxPrimitive.Label
      class={cn(
        "text-sm font-medium leading-none text-foreground peer-disabled:cursor-not-allowed peer-disabled:opacity-70",
        local.class,
      )}
      {...others}
    />
  );
};

// `variant="gradient"` branches the Control class string directly rather than an
// override-able prop - Kobalte's Control has no stable data-* hook to target externally.
type CheckboxRootProps<T extends ValidComponent = "div"> = Omit<CheckboxPrimitive.CheckboxRootProps<T>, "children"> & {
  class?: string | undefined;
  variant?: "default" | "gradient";
  // Narrowed from Kobalte's render-prop union - this wrapper only uses the plain-element form.
  children?: JSX.Element;
};

const Checkbox = <T extends ValidComponent = "div">(props: PolymorphicProps<T, CheckboxRootProps<T>>) => {
  const [local, others] = splitProps(props as CheckboxRootProps, ["class", "variant", "children"]);
  const controlClass =
    local.variant === "gradient"
      ? "size-4 shrink-0 rounded-sm border border-accent-indigo/40 ring-offset-background disabled:cursor-not-allowed disabled:opacity-50 peer-focus-visible:outline-none peer-focus-visible:ring-2 peer-focus-visible:ring-accent-indigo/50 peer-focus-visible:ring-offset-2 data-[checked]:border-transparent data-[indeterminate]:border-transparent data-[checked]:bg-accent-indigo data-[indeterminate]:bg-accent-indigo data-[checked]:text-white data-[indeterminate]:text-white"
      : "size-4 shrink-0 rounded-sm border border-primary ring-offset-background disabled:cursor-not-allowed disabled:opacity-50 peer-focus-visible:outline-none peer-focus-visible:ring-2 peer-focus-visible:ring-ring peer-focus-visible:ring-offset-2 data-[checked]:border-none data-[indeterminate]:border-none data-[checked]:bg-primary data-[indeterminate]:bg-primary data-[checked]:text-primary-foreground data-[indeterminate]:text-primary-foreground";

  return (
    <CheckboxPrimitive.Root class={cn("group relative flex items-center space-x-2", local.class)} {...others}>
      <CheckboxPrimitive.Input class="peer" />
      <CheckboxPrimitive.Control class={controlClass}>
        <CheckboxPrimitive.Indicator>
          <Switch>
            <Match when={!others.indeterminate}>
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="size-4"
              >
                <path d="M5 12l5 5l10 -10" />
              </svg>
            </Match>
            <Match when={others.indeterminate}>
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="size-4"
              >
                <path d="M5 12l14 0" />
              </svg>
            </Match>
          </Switch>
        </CheckboxPrimitive.Indicator>
      </CheckboxPrimitive.Control>
      {local.children}
    </CheckboxPrimitive.Root>
  );
};

export { Checkbox, CheckboxLabel };
