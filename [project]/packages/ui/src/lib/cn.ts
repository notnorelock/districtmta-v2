import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// Custom @theme colors (accent-indigo, accent-violet) must be registered explicitly, or
// tailwind-merge won't dedupe them against built-in colors and both classes survive.
const twMerge = extendTailwindMerge({
  extend: {
    theme: {
      colors: ["accent-indigo", "accent-violet"],
    },
  },
});

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
