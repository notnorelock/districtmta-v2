/** Mirrors the "loading.progress" payload from core_loading/client/DownloadTracker.lua. */
export interface DownloadProgress {
  visible: boolean;
  downloadedSize: number;
  totalSize: number;
}
