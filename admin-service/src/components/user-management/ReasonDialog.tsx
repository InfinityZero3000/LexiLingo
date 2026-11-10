import { useId, useState } from "react";
import { Dialog } from "../Dialog";
import { useI18n } from "../../lib/i18n";

export const MIN_REASON_LENGTH = 5;

type ReasonDialogProps = {
  title: string;
  description?: string;
  confirmLabel: string;
  danger?: boolean;
  busy?: boolean;
  error?: string | null;
  /** Fields that sit above the reason (amount, days…). */
  children?: React.ReactNode;
  /** Extra gate on top of the reason (e.g. a number must be valid). */
  canSubmit?: boolean;
  onSubmit: (reason: string) => void;
  onClose: () => void;
};

/** A money- or access-changing action must say why; the reason is written to the audit log. */
export const ReasonDialog = ({
  title, description, confirmLabel, danger, busy, error, children, canSubmit = true, onSubmit, onClose,
}: ReasonDialogProps) => {
  const { t } = useI18n();
  const [reason, setReason] = useState("");
  const hintId = useId();
  const valid = reason.trim().length >= MIN_REASON_LENGTH && canSubmit;

  return (
    <Dialog onClose={onClose} maxWidth={480}>
      <h3>{title}</h3>
      {description && <p className="text-muted">{description}</p>}
      <form
        className="form"
        onSubmit={(e) => {
          e.preventDefault();
          if (valid && !busy) onSubmit(reason.trim());
        }}
      >
        {children}
        <label>
          {t.support.reason}
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            maxLength={300}
            placeholder={t.support.reasonPlaceholder}
            aria-describedby={hintId}
            required
          />
        </label>
        <span id={hintId} className="form-hint">{t.support.reasonHint}</span>
        {error && <div className="form-error" role="alert">{error}</div>}
        <div className="table-actions">
          <button type="button" className="ghost-button" onClick={onClose}>{t.common.cancel}</button>
          <button type="submit" className={danger ? "ghost-button danger" : "primary-button"} disabled={!valid || busy}>
            {busy ? t.common.saving : confirmLabel}
          </button>
        </div>
      </form>
    </Dialog>
  );
};
