import { Show, type Component } from "solid-js";
import { Progress } from "@/components/ui/Progress";
import { TopographicBackground } from "@/components/common/TopographicBackground";
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
    <div class="relative flex h-full w-full flex-col items-center justify-center gap-4 overflow-hidden bg-background/60">
      <TopographicBackground />

      <span class="relative z-10 h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />

      <Show
        when={(() => {
          const progress = loadingStore.progress();
          return progress && progress.visible && progress.totalSize > 0 ? progress : null;
        })()}
        fallback={<p class="relative z-10 text-sm text-muted-foreground">{t()("app.loading")}</p>}
      >
        {(progress) => (
          <div class="relative z-10 flex w-full max-w-xs flex-col gap-2">
            <p class="text-center text-sm text-muted-foreground">
              {t()("loading.resourceCheck")} ({formatBytes(progress().downloadedSize)} / {formatBytes(progress().totalSize)})
            </p>

            <Progress value={Math.round((progress().downloadedSize / progress().totalSize) * 100)} />
          </div>
        )}
      </Show>
    </div>
  );
};
