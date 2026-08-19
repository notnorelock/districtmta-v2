import type { FlowComponent } from "solid-js";
import { Show } from "solid-js";
import { Transition } from "solid-transition-group";
import { useOverlay } from "@/components/common/OverlayProvider";

export interface OverlayProps {
  /** Overlay name, as toggled by UI.showOverlay/hideOverlay in Lua - never by this component itself. */
  name: string;
  /**
   * CSS transition-name prefix (Vue-style: `${transitionName}-enter-active`,
   * `${transitionName}-exit-active`, etc. - see styles/globals.css).
   */
  transitionName: string;
}

/**
 * Generic mount point for a script-toggled overlay (see
 * BrowserManager.lua's UI.showOverlay/hideOverlay module comment) with a
 * Vue-style out-in enter/leave transition. Visibility is entirely
 * server/client-Lua-driven via OverlayProvider/useOverlay - this
 * component only reacts, it never shows/hides itself. Must be used
 * inside an OverlayProvider (see App.tsx).
 */
export const Overlay: FlowComponent<OverlayProps> = (props) => {
  const overlay = useOverlay();

  return (
    <Transition
      name={props.transitionName}
      mode="outin"
      enterActiveClass={`${props.transitionName}-enter-active`}
      exitActiveClass={`${props.transitionName}-exit-active`}
      enterClass={`${props.transitionName}-enter-from`}
      exitToClass={`${props.transitionName}-exit-to`}
    >
      <Show when={overlay.isVisible(props.name)}>{props.children}</Show>
    </Transition>
  );
};
