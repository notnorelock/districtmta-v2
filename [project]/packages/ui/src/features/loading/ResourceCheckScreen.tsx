import { Show, type Component } from "solid-js";
import { loadingStore } from "@/stores/loading.store";
import { t } from "@/i18n";

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// Falls back to a plain spinner until the first loading.progress push arrives.
export const ResourceCheckScreen: Component = () => {
  return (
    <div class="flex h-full w-full flex-col items-center justify-center gap-4 bg-background/60">
      <span class="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />

      <Show
        when={(() => {
          const progress = loadingStore.progress();
          return progress && progress.visible && progress.totalSize > 0 ? progress : null;
        })()}
        fallback={<p class="text-sm text-muted-foreground">{t()("app.loading")}</p>}
      >
        {(progress) => (
          <div class="flex w-full max-w-xs flex-col gap-2">
            <p class="text-center text-sm text-muted-foreground">
              {t()("loading.resourceCheck")} ({formatBytes(progress().downloadedSize)} / {formatBytes(progress().totalSize)})
            </p>

            <div class="h-1.5 w-full overflow-hidden rounded-full bg-surface">
              <div
                class="h-full rounded-full bg-primary transition-all"
                style={{ width: `${Math.round((progress().downloadedSize / progress().totalSize) * 100)}%` }}
              />
            </div>
          </div>
        )}
      </Show>
    </div>
  );
};
