"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";
import { X } from "lucide-react";

export default function Modal({ title, onClose, children, className = "" }: {
  title: string; onClose: () => void; children: ReactNode; className?: string;
}) {
  const id = useId();
  const dialog = useRef<HTMLElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const controls = () => Array.from(dialog.current?.querySelectorAll<HTMLElement>("button:not(:disabled),a[href],input,select,[tabindex='0']") || []).filter(el => el.getClientRects().length);
    controls()[0]?.focus();
    function keyboard(event: KeyboardEvent) {
      if (event.key === "Escape") close.current();
      if (event.key !== "Tab") return;
      const elements = controls();
      if (event.shiftKey && document.activeElement === elements[0]) { event.preventDefault(); elements.at(-1)?.focus(); }
      else if (!event.shiftKey && document.activeElement === elements.at(-1)) { event.preventDefault(); elements[0]?.focus(); }
    }
    document.addEventListener("keydown", keyboard);
    return () => {
      document.body.style.overflow = oldOverflow;
      document.removeEventListener("keydown", keyboard);
      if (previous?.isConnected) previous.focus();
    };
  }, []);
  return <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) close.current(); }}>
    <section ref={dialog} className={`modal ${className}`} role="dialog" aria-modal="true" aria-labelledby={id}>
      <div className="modal-heading"><div><span className="overline">DAMA · FRIENDS EDITION</span><h2 id={id}>{title}</h2></div><button type="button" className="icon-button" onClick={onClose} aria-label="داخستن"><X size={21} /></button></div>
      {children}
    </section>
  </div>;
}
