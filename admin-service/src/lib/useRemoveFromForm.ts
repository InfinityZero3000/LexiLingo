import { useConfirm } from "../components/ConfirmDialog";
import { fillText } from "./deletion";
import { useI18n } from "./i18n";

/** Removing an empty row is silent; one the author has typed into asks first. */
export const useRemoveFromForm = () => {
  const confirm = useConfirm();
  const { t } = useI18n();
  return async (typed: string, remove: () => void) => {
    const name = typed.trim();
    if (name) {
      const message = fillText(t.deletion.removeFilled, { name });
      if (!(await confirm({ message, confirmLabel: t.deletion.remove, danger: true }))) return;
    }
    remove();
  };
};
