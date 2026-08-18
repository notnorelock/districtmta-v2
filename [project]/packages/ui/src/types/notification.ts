export type NotificationType = "success" | "error" | "info" | "warning";

export interface NotificationPayload {
  type: NotificationType;
  /** i18n key, e.g. "account.created" */
  title: string;
  /** i18n key, e.g. "account.created.description" */
  message?: string;
}

export interface Notification extends NotificationPayload {
  id: string;
  createdAt: number;
}
