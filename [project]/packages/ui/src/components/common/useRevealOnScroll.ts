import { createSignal, onCleanup } from "solid-js";

export function useRevealOnScroll() {
  const [visible, setVisible] = createSignal(false);
  let observer: IntersectionObserver | undefined;

  const ref = (el: Element) => {
    observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setVisible(true);
            observer?.disconnect();
          }
        }
      },
      { threshold: 0.15 },
    );
    observer.observe(el);
  };

  onCleanup(() => observer?.disconnect());

  return { ref, visible };
}
