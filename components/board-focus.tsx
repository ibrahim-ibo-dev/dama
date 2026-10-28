"use client";

import { useCallback, useLayoutEffect, useRef, type ReactNode } from "react";
import { X } from "lucide-react";
import "./board-focus.css";

export type BoardFocusProps = {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  status: string;
  canPlay: boolean;
};

/** A live board-only view. CSS covers the viewport immediately; native
 * fullscreen is a progressive enhancement when the browser permits it. */
export default function BoardFocus({ open, onClose, children, status, canPlay }: BoardFocusProps) {
  const overlayRef = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);
  const activeRef = useRef(false);
  const closingRef = useRef(false);
  const attemptedFullscreenRef = useRef(false);
  const enteredFullscreenRef = useRef(false);
  onCloseRef.current = onClose;

  const close = useCallback(() => {
    if (!activeRef.current || closingRef.current) return;
    closingRef.current = true;
    onCloseRef.current();
  }, []);

  useLayoutEffect(() => {
    if (!open) {
      attemptedFullscreenRef.current = false;
      enteredFullscreenRef.current = false;
      return;
    }
    const overlay = overlayRef.current;
    if (!overlay) return;
    const doc = overlay.ownerDocument;
    const previousFocus = doc.activeElement instanceof HTMLElement ? doc.activeElement : null;
    const previousOverflow = doc.body.style.overflow;
    activeRef.current = true;
    closingRef.current = false;
    enteredFullscreenRef.current = doc.fullscreenElement === overlay;
    doc.body.style.overflow = "hidden";

    function focusableElements() {
      return Array.from(overlay!.querySelectorAll<HTMLElement>(
        'button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      )).filter(element => element.tabIndex >= 0 && element.getClientRects().length > 0 && element.getAttribute("aria-hidden") !== "true");
    }

    function handleKeyboard(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        close();
        return;
      }
      if (event.key !== "Tab") return;
      const elements = focusableElements();
      const first = elements[0], last = elements.at(-1);
      if (!first) { event.preventDefault(); overlay?.focus(); return; }
      const focused = doc.activeElement;
      if (!overlay?.contains(focused)) {
        event.preventDefault();
        (event.shiftKey ? last : first)?.focus();
      } else if (event.shiftKey && focused === first) {
        event.preventDefault(); last?.focus();
      } else if (!event.shiftKey && focused === last) {
        event.preventDefault(); first.focus();
      }
    }

    function handleFullscreenChange() {
      if (doc.fullscreenElement === overlay) enteredFullscreenRef.current = true;
      else if (enteredFullscreenRef.current) {
        enteredFullscreenRef.current = false;
        close();
      }
    }

    doc.addEventListener("keydown", handleKeyboard, true);
    doc.addEventListener("fullscreenchange", handleFullscreenChange);
    const boardCell = overlay.querySelector<HTMLElement>('.board-focus__board [tabindex="0"]');
    (boardCell || focusableElements()[0] || overlay).focus({ preventScroll: true });

    if (!attemptedFullscreenRef.current && !doc.fullscreenElement && typeof overlay.requestFullscreen === "function") {
      attemptedFullscreenRef.current = true;
      try {
        void overlay.requestFullscreen({ navigationUI: "hide" }).then(() => {
          // A user can close the view before the fullscreen promise settles.
          // Effect replay in Strict Mode keeps the same active DOM node.
          if ((!activeRef.current || overlayRef.current !== overlay) && doc.fullscreenElement === overlay) {
            void doc.exitFullscreen().catch(() => {});
          }
        }).catch(() => {
          // Browsers without user activation or native support retain CSS fullscreen.
        });
      } catch {
        // Some older browsers throw synchronously instead of rejecting a promise.
      }
    }

    return () => {
      activeRef.current = false;
      doc.removeEventListener("keydown", handleKeyboard, true);
      doc.removeEventListener("fullscreenchange", handleFullscreenChange);
      doc.body.style.overflow = previousOverflow;
      // Deferring teardown lets React's immediate Strict Mode effect replay
      // reuse a pending native fullscreen request rather than canceling it.
      queueMicrotask(() => {
        if (activeRef.current && overlayRef.current === overlay) return;
        if (doc.fullscreenElement === overlay && typeof doc.exitFullscreen === "function") {
          void doc.exitFullscreen().catch(() => {});
        }
        const anotherDialog = doc.querySelector('[role="dialog"][aria-modal="true"]');
        if (!anotherDialog && previousFocus?.isConnected) previousFocus.focus({ preventScroll: true });
      });
    };
  }, [open, close]);

  if (!open) return null;

  return <div
    ref={overlayRef}
    className="board-focus"
    role="dialog"
    aria-modal="true"
    aria-label="دۆخی تەنیا تەختە"
    tabIndex={-1}
    data-can-play={canPlay ? "true" : "false"}
  >
    <button type="button" className="board-focus__close" onClick={close} aria-label="دەرچوون لە دۆخی تەنیا تەختە" title="دەرچوون (Esc)"><X size={18} strokeWidth={1.8} /></button>
    <div className="board-focus__board">{children}</div>
    <p className="board-focus__status" role="status" aria-live="polite" aria-atomic="true">{status}</p>
  </div>;
}
