import type { Component } from "solid-js";
import { t } from "@/i18n";

export const LoadingScreen: Component = () => {
  return (
    <div class="flex h-full w-full flex-col items-center justify-center gap-3 bg-background/60">
      <span class="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />
      <p class="text-sm text-muted-foreground">{t()("app.loading")}</p>
    </div>
  );
};
