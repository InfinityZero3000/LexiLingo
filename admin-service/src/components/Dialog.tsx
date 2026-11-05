import { useEffect, useId, useRef, type CSSProperties, type ReactNode } from "react";

const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

// Backdrop clicks do not close it: an accidental click used to throw away a half-filled form.
export const Dialog = ({
  onClose,
  maxWidth,
  style,
  children,
}: {
  onClose: () => void;
  maxWidth?: number;
  style?: CSSProperties;
  children: ReactNode;
}) => {
  const ref = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;
  const titleId = useId();

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const previous = document.activeElement as HTMLElement | null;

    const heading = el.querySelector<HTMLElement>("h1,h2,h3");
    if (heading) {
      heading.id ||= titleId;
      el.setAttribute("aria-labelledby", heading.id);
    }
    (el.querySelector<HTMLElement>("input,select,textarea") ?? el.querySelector<HTMLElement>(FOCUSABLE) ?? el).focus();

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        onCloseRef.current();
        return;
      }
      if (e.key !== "Tab") return;
      const items = Array.from(el.querySelectorAll<HTMLElement>(FOCUSABLE));
      if (items.length === 0) return e.preventDefault();
      const first = items[0];
      const last = items[items.length - 1];
      if (e.shiftKey && (document.activeElement === first || document.activeElement === el)) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      previous?.focus();
    };
  }, [titleId]);

  return (
    <div className="modal-overlay">
      <div
        ref={ref}
        className="modal-content"
        role="dialog"
        aria-modal="true"
        tabIndex={-1}
        style={{ maxWidth, ...style }}
      >
        {children}
      </div>
    </div>
  );
};
