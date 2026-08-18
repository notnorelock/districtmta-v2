import type { Component } from "solid-js";
import { AuthCard } from "./AuthCard";

export const LoginView: Component = () => {
  return (
    <div class="flex h-full w-full items-center justify-center bg-background/60">
      <AuthCard />
    </div>
  );
};
