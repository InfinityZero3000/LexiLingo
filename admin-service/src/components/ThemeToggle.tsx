import { Moon, Sun } from "lucide-react";
import { useTheme } from "../lib/theme";

export const ThemeToggle = ({ className = "" }: { className?: string }) => {
  const { theme, toggle } = useTheme();
  const label = theme === "dark" ? "Chuyển sang giao diện sáng" : "Chuyển sang giao diện tối";
  return (
    <button
      type="button"
      className={`theme-toggle ${className}`}
      onClick={toggle}
      aria-label={label}
      title={label}
    >
      {theme === "dark" ? <Sun size={16} /> : <Moon size={16} />}
    </button>
  );
};
