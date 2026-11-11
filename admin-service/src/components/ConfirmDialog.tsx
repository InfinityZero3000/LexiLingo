import { createContext, useCallback, useContext, useState, type ReactNode } from "react";
import { Dialog } from "./Dialog";
import { useI18n } from "../lib/i18n";

export type ConfirmOptions = {
  message: string;
  title?: string;
  confirmLabel?: string;
  danger?: boolean;
  requireText?: string;
};

type Confirm = (options: ConfirmOptions) => Promise<boolean>;

const ConfirmContext = createContext<Confirm>(() => Promise.resolve(false));

export const useConfirm = () => useContext(ConfirmContext);

export const ConfirmProvider = ({ children }: { children: ReactNode }) => {
  const { t } = useI18n();
  const [pending, setPending] = useState<{ options: ConfirmOptions; resolve: (ok: boolean) => void } | null>(null);
  const [typed, setTyped] = useState("");

  const confirm = useCallback<Confirm>(
    (options) =>
      new Promise<boolean>((resolve) => {
        setTyped("");
        setPending({ options, resolve });
      }),
    [],
  );

  const settle = (ok: boolean) => {
    pending?.resolve(ok);
    setPending(null);
  };

  const options = pending?.options;
  const blocked = !!options?.requireText && typed !== options.requireText;

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      {options && (
        <Dialog onClose={() => settle(false)} maxWidth={440}>
          <h3>{options.title ?? t.common.confirm}</h3>
          <p className="confirm-message">{options.message}</p>
          {options.requireText && (
            <label className="confirm-type">
              {t.common.typeToConfirm.replace("{value}", options.requireText)}
              <input value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" />
            </label>
          )}
          <div className="inline-actions confirm-actions">
            <button type="button" className="ghost-button" onClick={() => settle(false)}>
              {t.common.cancel}
            </button>
            <button
              type="button"
              className={options.danger ? "primary-button danger" : "primary-button"}
              disabled={blocked}
              onClick={() => settle(true)}
            >
              {options.confirmLabel ?? t.common.confirm}
            </button>
          </div>
        </Dialog>
      )}
    </ConfirmContext.Provider>
  );
};
