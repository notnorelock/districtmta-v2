import { createSignal } from "solid-js";
import { mta } from "@/lib/mta/MtaBridge";
import type { DownloadProgress } from "@/types/loading";

// Pushed client-side by core_loading/client/DownloadTracker.lua - never a server round trip.
const [progress, setProgress] = createSignal<DownloadProgress | null>(null);

export const loadingStore = {
  progress,
};

mta.on("loading.progress", (data) => {
  setProgress(data as DownloadProgress);
});
