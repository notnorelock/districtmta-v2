import type { Component, ComponentProps } from "solid-js";
import { splitProps } from "solid-js";

import { cn } from "@/lib/cn";

// New for the design-system pass (docs/DesignSystem.md). A genuine
// tabular-data primitive - no such component exists anywhere in the
// app today (every "list" - inventory rows, member rows, group vehicle
// rows, the dashboard's own settings/account rows - is a hand-rolled
// .row/.rowLabel div pattern repeated per-feature). Composable pieces
// (Root/Header/Body/Row/Head/Cell), same sub-component export pattern
// as Card.tsx, rather than one monolithic component - lets callers keep
// using a plain <div> row shape where a real <table> element's layout
// semantics aren't needed, while providing a real option for genuinely
// tabular data. Sharp corners/hairline borders, no shadow - matches
// Card's own updated convention and the dashboard's established
// "solid background + hairline border" rule.
const TableRoot: Component<ComponentProps<"div">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);
  return (
    <div class={cn("w-full overflow-x-auto border border-border", local.class)} {...others}>
      <table class="w-full caption-bottom text-sm">{others.children}</table>
    </div>
  );
};

const TableHeader: Component<ComponentProps<"thead">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);
  return <thead class={cn("border-b border-border bg-surface-elevated", local.class)} {...others} />;
};

const TableBody: Component<ComponentProps<"tbody">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);
  return <tbody class={cn("[&_tr:last-child]:border-0", local.class)} {...others} />;
};

const TableRow: Component<ComponentProps<"tr">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);
  return (
    <tr
      class={cn(
        "border-b border-border/40 transition-colors duration-fast ease-out hover:bg-secondary/40",
        local.class,
      )}
      {...others}
    />
  );
};

const TableHead: Component<ComponentProps<"th">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);
  return (
    <th
      class={cn(
        "h-9 px-4 text-left align-middle font-mono text-2xs font-medium uppercase tracking-wide text-muted-foreground",
        local.class,
      )}
      {...others}
    />
  );
};

const TableCell: Component<ComponentProps<"td">> = (props) => {
  const [local, others] = splitProps(props, ["class"]);
  return <td class={cn("px-4 py-3 align-middle text-sm text-foreground", local.class)} {...others} />;
};

export { TableRoot, TableHeader, TableBody, TableRow, TableHead, TableCell };
