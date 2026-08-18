import type { Component } from "solid-js";
import { Button } from "@/components/ui/Button";
import { t } from "@/i18n";

export interface ErrorScreenProps {
  onRetry: () => void;
}

export const ErrorScreen: Component<ErrorScreenProps> = (props) => {
  return (
    <div class="flex h-full w-full flex-col items-center justify-center gap-4 bg-background/60 p-4 text-center">
      <p class="text-base font-medium text-foreground">{t()("app.error.title")}</p>
      <Button variant="secondary" onClick={() => props.onRetry()}>
        {t()("app.error.retry")}
      </Button>
    </div>
  );
};
