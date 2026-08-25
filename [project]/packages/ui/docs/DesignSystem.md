# District UI — Design System

Status: pilot foundation, rolled out to the F10 player dashboard only.
This is the first design-system documentation in this codebase — see
`styles/globals.css`'s own `@theme` block for the token source of truth;
this document explains the *why* and *when* behind those tokens and the
shared components in `components/ui/`.

## 1. Tokens

### 1.1 Color

Defined in `src/styles/globals.css`'s `@theme` block. Semantic naming
follows shadcn's convention (background/foreground pairs per role) so
ported component class strings (`bg-primary`, `text-muted-foreground`, …)
work unmodified.

| Token | Value | Role |
|---|---|---|
| `--color-background` | `#0a0908` | App/window background |
| `--color-foreground` | `#efebe8` | Default text |
| `--color-card` / `--color-popover` / `--color-surface` | `#121110` | Panel surfaces |
| `--color-surface-elevated` | `#17150f` | Raised surface (e.g. table header) |
| `--color-border` / `--color-input` | `#232019` | Hairline borders |
| `--color-primary` / `--color-ring` | `#fc8c5b` | Brand accent, focus rings |
| `--color-secondary` / `--color-accent` | `#322820` | Muted fills (hover states, tracks) |
| `--color-destructive` / `--color-danger` | `#e5484d` | Errors, destructive actions |
| `--color-success` | `#3dd68c` | Success states |
| `--color-warning` | `#f2b84b` | Warning states |
| `--color-muted` / `--color-muted-foreground` | `#8c8078` / `#b8aca2` | De-emphasized text |
| `--color-accent-indigo` / `--color-accent-violet` | `#ffab48` / `#dc604f` | Gradient endpoints (Button `variant="gradient"`, auth panel) |

`--color-primary` is intentionally unchanged across every visual pass so
far — this is a shape/type/motion redesign, not a rebrand.

### 1.2 Typography

| Token | Size | Line-height | Notes |
|---|---|---|---|
| `--text-2xs` | `0.625rem` (10px) | `1rem` | New this pass — promotes the `text-[10px]` arbitrary value already used independently in 5 files to a real token |
| `text-xs` … `text-3xl` | Tailwind defaults | Tailwind defaults | Not redeclared — Tailwind v4's built-in `theme.css` ships these already and they merge into this project's theme automatically |

Font faces: `--font-sans`/`--font-display` (Titillium Web), `--font-mono`
(JetBrains Mono, bundled locally as `.ttf` files — CEF in-game has no
reliable internet access for players, ruling out a Google Fonts
dependency).

### 1.3 The 3-way hierarchy rule

| Role | Font | Size | Case/Tracking | Example |
|---|---|---|---|---|
| **Heading** | `font-display` (Titillium Web) | `text-lg` / `text-xl` / `text-2xl` | `tracking-tight`, sentence case | Card/section titles |
| **Label/Data** ("eyebrow" family) | `font-mono` (JetBrains Mono) | `text-2xs` / `text-xs` | `uppercase tracking-wide` / `tracking-widest` | Row labels, captions, stat readouts, IDs |
| **Body** | `font-sans` (Titillium Web) | `text-sm` / `text-base` | normal case | Paragraph text, row values, descriptions |

Before this pass, 93% of all text-size usage app-wide was flat
`text-xs`/`text-sm` with no hierarchy signal beyond size. This table is
the rule going forward: reach for the Label/Data treatment (mono,
uppercase, tracked) whenever a piece of text names or categorizes a
value, not whenever it merely happens to be small.

### 1.4 Spacing / density tiers

No new spacing tokens — Tailwind's default 4px-base scale is used
everywhere and already expresses a real, convergent rhythm across two
legitimate density tiers. This section documents that rhythm rather than
replacing it.

- **Dashboard-scale** (full-screen chrome — the F10 dashboard, and any
  future full-window screen): `px-6 py-4` topbar, `p-8` content padding,
  `gap-6` between major sections, `gap-4` for related groups.
- **Panel-scale** (compact overlays — inventory, groups, scoreboard,
  vehicle storage): `px-4 py-3` for row/header padding, `px-4 py-8` for
  empty states, `p-2` for icon rails, half-step `gap-1.5`/`gap-2.5`
  specifically for icon+label pairs.

Pick the tier that matches the surface you're building, not by feel —
a full-window screen should read as roomier than a compact side panel.

### 1.5 Motion

| Token | Value | Usage |
|---|---|---|
| `--transition-duration-fast` | `150ms` | Hover/active feedback (buttons, nav rows, table rows), quick fade/scale overlays |
| `--transition-duration-base` | `250ms` | Standard enter/exit transitions (HUD, world interaction) |
| `--transition-duration-slow` | `350ms` | Larger surface changes (auth panel height/slide, full-screen blackout fade) |
| `--ease-out` | Tailwind default | The default easing for nearly everything — use unless a block below calls for something else |
| `--ease-height` | `cubic-bezier(0.36, 0.66, 0.04, 1)` | Auth panel's height-resize transition specifically |
| `--ease-overshoot` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Deliberate spring/overshoot — currently only the vehicle radial menu's entrance |

`duration-*` utilities are generated from Tailwind v4's
`--transition-duration-*` theme namespace (not `--duration-*`) — pair
them with a `duration-*` class directly, e.g.
`class="transition-colors duration-fast ease-out"`, no arbitrary-value
syntax needed. `globals.css`'s own hand-rolled overlay enter/exit blocks
(`.hud-*`, `.blackout-*`, `.scoreboard-*`, etc.) reference these same
tokens via `var(--transition-duration-fast)` etc. since those blocks are
plain CSS driven by solid-transition-group, not Tailwind utility classes.

### Icon sizing

Not tokenized — a plain numeric convention via `size={N}` props on
`lucide-solid` icons, no className-based sizing:

- **13–14px** — inline icons beside text (most common case)
- **16px** — standalone icons
- **18px** — list-row leading icons

## 2. Component catalog

All in `src/components/ui/`. `cva` (class-variance-authority) + `cn`
(`@/lib/cn`) is the standard pattern for variant-driven primitives.

### Badge

Status/category chip. Square by default (no `rounded-full`), matching
the terminal-tile direction. Variants: `default` / `primary` / `success`
/ `warning` / `danger` / `muted`. Sizes: `default` / `sm` / `dot` (a
small circular indicator with no children, for cases that specifically
need the dot shape — e.g. an online/offline marker).

```tsx
<Badge variant="success">Online</Badge>
<Badge variant="danger" size="dot" />
```

Use for: short status/category labels. Don't use for: anything with a
click handler (use `Button` instead) or long text (it doesn't wrap).

### Progress

Track + fill bar, replacing ad-hoc div-pair patterns like the
dashboard's former `.levelBar`/`.levelBarFill`. Sizes: `default` / `sm`
/ `lg`. Variants: `default` / `success` / `warning` / `danger`.

```tsx
<Progress value={35} />
```

`value` is 0–100 and is **not** clamped internally — pass a pre-clamped
number.

### Table (`TableRoot` / `TableHeader` / `TableBody` / `TableRow` / `TableHead` / `TableCell`)

Composable, mirrors `Card.tsx`'s sub-component export pattern. Use for
genuinely tabular data (rows sharing the same columns). Don't force
existing `.row`/`.rowLabel` div patterns into a `Table` just because
data happens to be listed — those remain fine for label/value pairs
that aren't really multi-column data.

```tsx
<TableRoot>
  <TableHeader>
    <TableRow>
      <TableHead>Name</TableHead>
      <TableHead>Status</TableHead>
    </TableRow>
  </TableHeader>
  <TableBody>
    <TableRow>
      <TableCell>Alice</TableCell>
      <TableCell><Badge variant="success">Online</Badge></TableCell>
    </TableRow>
  </TableBody>
</TableRoot>
```

### Skeleton

Loading placeholder — a plain pulsing block, for content that streams
in and would otherwise blank-flash (e.g. a `Table` full of rows loading
from the network).

```tsx
<Skeleton class="h-4 w-32" />
```

Don't use for quick (<300ms) actions like a form submit — keep
`Button`'s built-in `loading` spinner for those; a skeleton reads as
"this will take a moment," which is the wrong signal for a fast action.

## 3. Rollout status

**Using the system today:** the F10 player dashboard only
(`features/dashboard/*`), plus the shared primitives `Button.tsx` and
`Card.tsx` (which every feature already imports, so their motion/shadow
updates apply globally even though this pass doesn't redesign those
other features' own layouts).

**Pending a future pass:** auth/login, HUD, inventory, groups,
scoreboard, world map, vehicle storage/interaction/menu, blackout,
license exam, duty indicator. Do not assume any of these follow this
document's typography/motion rules until this section says otherwise —
they still use their pre-existing, un-migrated styling.
