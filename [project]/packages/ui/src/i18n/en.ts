import type { pl } from "./pl";

export const en: Record<keyof typeof pl, string> = {
  "app.loading": "Loading...",
  "app.error.title": "Something went wrong",
  "app.error.retry": "Try again",

  "loading.resourceCheck": "Downloading resources",

  "auth.tabs.login": "Login",
  "auth.tabs.register": "Register",

  "auth.login.title": "Welcome",
  "auth.login.subtitle": "Enter your login or email and password to sign in",
  "auth.login.login": "Login or email",
  "auth.login.loginPlaceholder": "YourNick or you@email.com",
  "auth.login.email": "Email address",
  "auth.login.emailPlaceholder": "you@email.com",
  "auth.login.password": "Password",
  "auth.login.passwordPlaceholder": "Enter password",
  "auth.password.show": "Show password",
  "auth.password.hide": "Hide password",
  "auth.login.submit": "Sign in",
  "auth.login.submitting": "Connecting...",
  "auth.login.rememberMe": "Remember me on this device",

  "auth.register.title": "Register",
  "auth.register.subtitle": "Enter a login, email and password to create an account",
  "auth.register.confirmPassword": "Confirm password",
  "auth.register.confirmPasswordPlaceholder": "Repeat password",
  "auth.register.submit": "Create account",
  "auth.register.passwordMismatch": "Passwords do not match",

  "auth.error.INVALID_LOGIN": "Login must be 3-24 characters: letters, numbers, underscore",
  "auth.error.INVALID_EMAIL": "Email address is not valid",
  "auth.error.INVALID_PASSWORD": "Password must be 8-128 characters",
  "auth.error.INVALID_CREDENTIALS": "Invalid login, email or password",
  "auth.error.ACCOUNT_BANNED": "This account is banned",
  "auth.error.INVALID_ARGUMENTS": "Invalid form data",
  "auth.error.ACCOUNT_ALREADY_EXISTS": "Login or email is already taken",
  "auth.error.RATE_LIMITED": "Too many attempts. Please wait a moment.",
  "auth.error.REQUEST_TIMEOUT": "The server did not respond in time",
  "auth.error.INTERNAL_ERROR": "A server error occurred",
  "auth.error.RESOURCE_UNAVAILABLE": "The service is temporarily unavailable",
  "auth.error.UNKNOWN_ENDPOINT": "Unknown request",
  "auth.error.NOT_AUTHENTICATED": "You must be logged in",
  "auth.error.ACCOUNT_NOT_FOUND": "Account not found",
  "auth.error.INVALID_REQUEST": "Invalid request",
  "auth.error.INVALID_SPAWN": "Invalid spawn location",
  "auth.error.generic": "Could not connect to your account",

  "account.created": "Account created",
  "account.created.description": "Your account has been created successfully",

  "spawn.title": "Choose your spawn location",
  "spawn.subtitle": "Decide where you want to start playing",
  "spawn.select": "Select",
  "spawn.entering": "Entering the world...",

  "notification.dismiss": "Dismiss",

  "blackout.title": "You are unconscious",
  "blackout.waitingForHelp": "Wait for medical help.",
  "blackout.selfReviveHint.before": "If no one comes, press",
  "blackout.selfReviveHint.after": "to get back up.",

  "radio.buffering": "Buffering...",
  "radio.subtitle": "Vehicle radio",
  "radio.footerLabel": "Music from phone",
  "radio.off": "Radio off",
};
