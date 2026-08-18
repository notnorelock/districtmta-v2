import { createStore, produce } from "solid-js/store";
import type { Notification, NotificationPayload } from "@/types/notification";
import { mta } from "@/lib/mta/MtaBridge";

const [notifications, setNotifications] = createStore<Notification[]>([]);

const AUTO_DISMISS_MS = 5000;

function push(payload: NotificationPayload): void {
  const notification: Notification = {
    ...payload,
    id: crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
    createdAt: Date.now(),
  };

  setNotifications(produce((list) => list.push(notification)));

  window.setTimeout(() => dismiss(notification.id), AUTO_DISMISS_MS);
}

function dismiss(id: string): void {
  setNotifications((list) => list.filter((notification) => notification.id !== id));
}

export const notificationStore = {
  items: notifications,
  dismiss,
  success: (title: string, message?: string) => push({ type: "success", title, message }),
  error: (title: string, message?: string) => push({ type: "error", title, message }),
  info: (title: string, message?: string) => push({ type: "info", title, message }),
  warning: (title: string, message?: string) => push({ type: "warning", title, message }),
};

mta.on("notification.created", (data) => {
  push(data as NotificationPayload);
});
