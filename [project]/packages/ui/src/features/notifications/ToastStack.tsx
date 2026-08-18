import { For, type Component } from "solid-js";
import { Toast } from "@/components/ui/Toast";
import { notificationStore } from "@/stores/notification.store";

export const ToastStack: Component = () => {
  return (
    <div class="pointer-events-none fixed right-4 top-4 z-[100] flex flex-col gap-2">
      <For each={notificationStore.items}>
        {(notification) => <Toast notification={notification} onDismiss={notificationStore.dismiss} />}
      </For>
    </div>
  );
};
