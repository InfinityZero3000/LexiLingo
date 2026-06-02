import React, { useCallback, useEffect, useRef, useState } from "react";
import { Lock, ShieldAlert, Check } from "lucide-react";

interface ConfigLockProps {
  children: React.ReactNode;
}

const PIN_LENGTH = 5;
const CORRECT_PIN = "12345";

const isEditableTarget = (target: EventTarget | null) => {
  if (!(target instanceof HTMLElement)) {
    return false;
  }

  return (
    target.tagName === "INPUT" ||
    target.tagName === "TEXTAREA" ||
    target.isContentEditable
  );
};

export const ConfigLock = ({ children }: ConfigLockProps) => {
  const [unlocked, setUnlocked] = useState(() => {
    return sessionStorage.getItem("lexilingo_config_unlocked") === "true";
  });
  const [pin, setPin] = useState("");
  const [error, setError] = useState(false);
  const [shake, setShake] = useState(false);
  const [success, setSuccess] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const unlockTimerRef = useRef<ReturnType<typeof window.setTimeout> | null>(null);
  const resetTimerRef = useRef<ReturnType<typeof window.setTimeout> | null>(null);
  const shakeTimerRef = useRef<ReturnType<typeof window.setTimeout> | null>(null);

  const focusPinInput = useCallback(() => {
    inputRef.current?.focus({ preventScroll: true });
  }, []);

  const clearTimers = useCallback(() => {
    if (unlockTimerRef.current) {
      window.clearTimeout(unlockTimerRef.current);
      unlockTimerRef.current = null;
    }

    if (resetTimerRef.current) {
      window.clearTimeout(resetTimerRef.current);
      resetTimerRef.current = null;
    }

    if (shakeTimerRef.current) {
      window.clearTimeout(shakeTimerRef.current);
      shakeTimerRef.current = null;
    }
  }, []);

  const updatePin = useCallback((value: string) => {
    if (success) {
      return;
    }

    const nextPin = value.replace(/\D/g, "").slice(0, PIN_LENGTH);
    clearTimers();
    setPin(nextPin);
    setError(false);
    setShake(false);

    if (nextPin === CORRECT_PIN) {
      setSuccess(true);
      unlockTimerRef.current = window.setTimeout(() => {
        sessionStorage.setItem("lexilingo_config_unlocked", "true");
        setUnlocked(true);
      }, 600);
      return;
    }

    if (nextPin.length === PIN_LENGTH) {
      resetTimerRef.current = window.setTimeout(() => {
        setShake(true);
        setError(true);
        setPin("");
        focusPinInput();
        shakeTimerRef.current = window.setTimeout(() => setShake(false), 500);
      }, 200);
    }
  }, [clearTimers, focusPinInput, success]);

  const handleKeyPress = useCallback((num: string) => {
    if (pin.length < PIN_LENGTH) {
      updatePin(pin + num);
      focusPinInput();
    }
  }, [focusPinInput, pin, updatePin]);

  const handleBackspace = useCallback(() => {
    updatePin(pin.slice(0, -1));
    focusPinInput();
  }, [focusPinInput, pin, updatePin]);

  const handleClear = useCallback(() => {
    updatePin("");
    focusPinInput();
  }, [focusPinInput, updatePin]);

  useEffect(() => {
    if (!unlocked) {
      const focusTimer = window.setTimeout(focusPinInput, 50);
      return () => window.clearTimeout(focusTimer);
    }
  }, [focusPinInput, unlocked]);

  useEffect(() => {
    if (unlocked) {
      return undefined;
    }

    const handleKeyboardInput = (event: KeyboardEvent) => {
      if (event.ctrlKey || event.metaKey || event.altKey || isEditableTarget(event.target)) {
        return;
      }

      if (/^\d$/.test(event.key)) {
        event.preventDefault();
        handleKeyPress(event.key);
        return;
      }

      if (event.key === "Backspace") {
        event.preventDefault();
        handleBackspace();
        return;
      }

      if (event.key === "Delete" || event.key === "Escape") {
        event.preventDefault();
        handleClear();
      }
    };

    window.addEventListener("keydown", handleKeyboardInput);
    return () => window.removeEventListener("keydown", handleKeyboardInput);
  }, [handleBackspace, handleClear, handleKeyPress, unlocked]);

  useEffect(() => {
    return () => clearTimers();
  }, [clearTimers]);

  if (unlocked) {
    return <>{children}</>;
  }

  return (
    <div className="lock-overlay">
      <style>{`
        .lock-overlay {
          position: fixed;
          top: 0;
          left: 0;
          width: 100vw;
          height: 100vh;
          background: rgba(225, 242, 255, 0.45);
          backdrop-filter: blur(12px);
          -webkit-backdrop-filter: blur(12px);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 99999;
          font-family: 'Instrument Sans', system-ui, -apple-system, sans-serif;
          color: var(--text, #1a2835);
        }

        .lock-card {
          background: linear-gradient(180deg, #ffffff 0%, #f8fcff 100%);
          border: 1px solid var(--line, #b8d9f5);
          border-radius: 24px;
          padding: 40px;
          width: 380px;
          max-width: 90%;
          box-shadow: 0 20px 44px rgba(10, 50, 90, 0.12);
          display: flex;
          flex-direction: column;
          align-items: center;
          text-align: center;
          position: relative;
          overflow: hidden;
        }

        .lock-card::before {
          content: '';
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 4px;
          background: linear-gradient(90deg, var(--accent, #ff4d00) 0%, var(--accent-2, #2aa7a1) 100%);
        }

        .lock-icon-wrapper {
          width: 64px;
          height: 64px;
          border-radius: 18px;
          background: rgba(255, 77, 0, 0.08);
          border: 1px solid rgba(255, 77, 0, 0.15);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 24px;
          color: var(--accent, #ff4d00);
          transition: all 0.3s ease;
        }

        .lock-icon-wrapper.success {
          background: rgba(42, 167, 161, 0.12);
          border-color: rgba(42, 167, 161, 0.3);
          color: var(--accent-2, #2aa7a1);
          transform: scale(1.05);
        }

        .lock-icon-wrapper.error {
          background: rgba(218, 50, 76, 0.1);
          border-color: rgba(218, 50, 76, 0.3);
          color: #b7324c;
        }

        .lock-title {
          font-family: 'Space Grotesk', 'Instrument Sans', sans-serif;
          font-size: 22px;
          font-weight: 700;
          margin: 0 0 10px;
          letter-spacing: -0.015em;
          color: var(--text, #1a2835);
        }

        .lock-subtitle {
          font-size: 14px;
          color: var(--muted, #4a6070);
          margin-bottom: 32px;
          line-height: 1.5;
        }

        .pin-dots {
          display: flex;
          gap: 16px;
          margin-bottom: 36px;
          justify-content: center;
        }

        .pin-input {
          position: absolute;
          width: 1px;
          height: 1px;
          opacity: 0;
          pointer-events: none;
        }

        .pin-dot {
          width: 14px;
          height: 14px;
          border-radius: 50%;
          border: 2px solid var(--line, #b8d9f5);
          background: transparent;
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .pin-dot.filled {
          background: var(--accent, #ff4d00);
          border-color: var(--accent, #ff4d00);
          transform: scale(1.15);
          box-shadow: 0 0 10px rgba(255, 77, 0, 0.3);
        }

        .pin-dot.success {
          background: var(--accent-2, #2aa7a1);
          border-color: var(--accent-2, #2aa7a1);
          box-shadow: 0 0 10px rgba(42, 167, 161, 0.4);
        }

        .pin-dot.error {
          background: #b7324c;
          border-color: #b7324c;
          box-shadow: 0 0 10px rgba(183, 50, 76, 0.4);
        }

        .keypad {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 16px;
          width: 100%;
        }

        .keypad-btn {
          height: 56px;
          border-radius: 16px;
          background: #ffffff;
          border: 1px solid var(--line, #b8d9f5);
          color: var(--text, #1a2835);
          font-size: 18px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.15s ease;
          display: flex;
          align-items: center;
          justify-content: center;
          user-select: none;
          box-shadow: 0 2px 4px rgba(10, 50, 90, 0.04);
        }

        .keypad-btn:hover {
          background: var(--panel-soft, #cde8ff);
          border-color: var(--line-strong, #9dc2e2);
          transform: translateY(-1px);
          box-shadow: 0 4px 8px rgba(10, 50, 90, 0.08);
        }

        .keypad-btn:active {
          transform: translateY(1px);
          background: var(--line-strong, #9dc2e2);
          box-shadow: none;
        }

        .keypad-btn.action-btn {
          font-size: 14px;
          font-weight: 600;
          color: var(--muted, #4a6070);
          background: rgba(225, 242, 255, 0.35);
        }

        .keypad-btn.action-btn:hover {
          background: var(--panel-soft, #cde8ff);
          color: var(--text, #1a2835);
        }

        .shake {
          animation: shake 0.4s ease-in-out;
        }

        @keyframes shake {
          0%, 100% { transform: translateX(0); }
          20%, 60% { transform: translateX(-8px); }
          40%, 80% { transform: translateX(8px); }
        }

        .error-message {
          color: #b7324c;
          font-size: 13px;
          margin-top: -16px;
          margin-bottom: 24px;
          min-height: 20px;
          display: flex;
          align-items: center;
          gap: 6px;
          animation: fadeIn 0.2s ease;
        }

        @keyframes fadeIn {
          from { opacity: 0; transform: translateY(-4px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>

      <div className={`lock-card ${shake ? "shake" : ""}`} onClick={focusPinInput}>
        <div className={`lock-icon-wrapper ${success ? "success" : error ? "error" : ""}`}>
          {success ? <Check size={28} /> : error ? <ShieldAlert size={28} /> : <Lock size={28} />}
        </div>

        <h2 className="lock-title">Nhập mật mã bảo mật</h2>
        <p className="lock-subtitle">Cài đặt hệ thống đang được khóa. Vui lòng nhập mã PIN để tiếp tục cấu hình.</p>

        <input
          ref={inputRef}
          className="pin-input"
          value={pin}
          onChange={(event) => updatePin(event.target.value)}
          inputMode="numeric"
          pattern="[0-9]*"
          maxLength={PIN_LENGTH}
          autoComplete="one-time-code"
          aria-label="Nhập mã PIN bảo mật"
          autoFocus
        />

        {error && (
          <div className="error-message">
            <ShieldAlert size={14} /> Mật mã không đúng, vui lòng thử lại!
          </div>
        )}

        <div className="pin-dots">
          {[...Array(5)].map((_, i) => (
            <div
              key={i}
              aria-hidden="true"
              className={`pin-dot ${
                success ? "success" : error ? "error" : i < pin.length ? "filled" : ""
              }`}
            />
          ))}
        </div>

        <div className="keypad">
          {["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((num) => (
            <button
              key={num}
              type="button"
              className="keypad-btn"
              onClick={() => handleKeyPress(num)}
              aria-label={`Nhập số ${num}`}
            >
              {num}
            </button>
          ))}
          <button type="button" className="keypad-btn action-btn" onClick={handleClear}>
            Xóa
          </button>
          <button
            type="button"
            className="keypad-btn"
            onClick={() => handleKeyPress("0")}
            aria-label="Nhập số 0"
          >
            0
          </button>
          <button
            type="button"
            className="keypad-btn action-btn"
            onClick={handleBackspace}
            aria-label="Xóa một số"
          >
            ←
          </button>
        </div>
      </div>
    </div>
  );
};
