import type { JSX } from "solid-js";
import { Show, createSignal, onCleanup, onMount } from "solid-js";
import { isServer } from "solid-js/web";

export type MarqueeMode = "bounce" | "delayed" | "loop";

export interface MarqueeProps {
    readonly children: JSX.Element;
    readonly class?: string;
    /**
     * - "bounce" (default): continuous back-and-forth, no pause at the ends.
     * - "delayed": holds at each end (~3-5s, scaled by `durationSeconds`)
     *   instead of reversing immediately.
     * - "loop": one-directional, seamless ticker scroll — never reverses,
     *   wraps back to the start. Renders two copies of the content internally.
     */
    readonly mode?: MarqueeMode;
    /** Total animation-duration in seconds. Defaults: 10s (bounce/loop) / 16s (delayed). */
    readonly durationSeconds?: number;
    /** "loop" mode only: gap in px between the wrapping copy and the next repeat. Default 48. */
    readonly loopGapPx?: number;
}

export function Marquee(props: MarqueeProps): JSX.Element {
    let containerRef: HTMLDivElement | undefined;
    let contentRef: HTMLSpanElement | undefined;
    const [overflowPx, setOverflowPx] = createSignal(0);
    const [contentWidthPx, setContentWidthPx] = createSignal(0);
    const mode = () => props.mode ?? "bounce";

    function measure(): void {
        if (!containerRef || !contentRef) {
            return;
        }
        setContentWidthPx(contentRef.scrollWidth);
        setOverflowPx(Math.max(0, contentRef.scrollWidth - containerRef.clientWidth));
    }

    onMount(() => {
        if (isServer) {
            return;
        }
        measure();

        const observer = new ResizeObserver(() => requestAnimationFrame(measure));
        if (containerRef) {
            observer.observe(containerRef);
        }
        onCleanup(() => observer.disconnect());
    });

    const overflowing = () => overflowPx() > 0;

    const trackAnimation = () => {
        if (!overflowing()) {
            return undefined;
        }
        switch (mode()) {
            case "delayed":
                return `marquee-slide-delayed ${props.durationSeconds ?? 16}s linear infinite`;
            case "loop":
                return `marquee-loop ${props.durationSeconds ?? 10}s linear infinite`;
            default:
                return `marquee-slide ${props.durationSeconds ?? 10}s linear infinite alternate`;
        }
    };

    return (
        <div ref={containerRef} class={`overflow-hidden whitespace-nowrap ${props.class ?? ""}`}>
            <span
                class="inline-flex"
                style={{
                    "--marquee-overflow": `${overflowPx()}px`,
                    "--marquee-content-width": `${contentWidthPx()}px`,
                    "--marquee-gap": `${props.loopGapPx ?? 48}px`,
                    animation: trackAnimation(),
                }}
            >
                <span ref={contentRef} class="inline-block shrink-0">
                    {props.children}
                </span>
                <Show when={mode() === "loop" && overflowing()}>
                    <span
                        aria-hidden="true"
                        class="inline-block shrink-0"
                        style={{ "margin-left": `${props.loopGapPx ?? 48}px` }}
                    >
                        {props.children}
                    </span>
                </Show>
            </span>
        </div>
    );
}