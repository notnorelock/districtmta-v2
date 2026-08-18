import { Show, type Component } from "solid-js";
import { cva } from "class-variance-authority";
import { cn } from "@/lib/cn";
import type { Notification } from "@/types/notification";
import { t } from "@/i18n";

const toastVariants = cva(
  "pointer-events-auto flex w-80 items-start gap-3 rounded-md border p-3 shadow-lg backdrop-blur-sm animate-in fade-in slide-in-from-right-4",
  {
    variants: {
      type: {
        success: "border-success/30 bg-success/10 text-foreground",
        error: "border-danger/30 bg-danger/10 text-foreground",
        info: "border-border bg-surface-elevated text-foreground",
        warning: "border-warning/30 bg-warning/10 text-foreground",
      },
    },
  },
);

const dotVariants = cva("mt-1 h-2 w-2 shrink-0 rounded-full", {
  variants: {
    type: {
      success: "bg-success",
      error: "bg-danger",
      info: "bg-primary",
      warning: "bg-warning",
    },
  },
});

export interface ToastProps {
  notification: Notification;
  onDismiss: (id: string) => void;
}

export const Toast: Component<ToastProps> = (props) => {
  return (
    <div class={cn(toastVariants({ type: props.notification.type }))} role="status">
      <span class={cn(dotVariants({ type: props.notification.type }))} />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium leading-tight">{t()(props.notification.title)}</p>
        <Show when={props.notification.message}>
          <p class="mt-0.5 text-xs text-muted-foreground">{t()(props.notification.message!)}</p>
        </Show>
      </div>
      <button
        type="button"
        class="text-muted-foreground transition-colors hover:text-foreground"
        aria-label={t()("notification.dismiss")}
        onClick={() => props.onDismiss(props.notification.id)}
      >
        ×
      </button>
    </div>
  );
};
