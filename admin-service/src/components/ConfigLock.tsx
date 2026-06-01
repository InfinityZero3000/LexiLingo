import React, { useState } from "react";
import { Lock, ShieldAlert, Check } from "lucide-react";

interface ConfigLockProps {
  children: React.ReactNode;
}

export const ConfigLock = ({ children }: ConfigLockProps) => {
  const [unlocked, setUnlocked] = useState(() => {
    return sessionStorage.getItem("lexilingo_config_unlocked") === "true";
  });
  const [pin, setPin] = useState("");
  const [error, setError] = useState(false);
  const [shake, setShake] = useState(false);
  const [success, setSuccess] = useState(false);

  const correctPin = "12345";

  const handleKeyPress = (num: string) => {
    if (pin.length < 5) {
      const nextPin = pin + num;
      setPin(nextPin);
      setError(false);

      if (nextPin === correctPin) {
        setSuccess(true);
        setTimeout(() => {
          sessionStorage.setItem("lexilingo_config_unlocked", "true");
          setUnlocked(true);
        }, 600);
      } else if (nextPin.length === 5) {
        // Wrong pin entered
        setTimeout(() => {
          setShake(true);
          setError(true);
          setPin("");
          setTimeout(() => setShake(false), 500);
        }, 200);
      }
    }
  };

  const handleBackspace = () => {
    setPin(pin.slice(0, -1));
    setError(false);
  };

  const handleClear = () => {
    setPin("");
    setError(false);
  };

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

      <div className={`lock-card ${shake ? "shake" : ""}`}>
        <div className={`lock-icon-wrapper ${success ? "success" : error ? "error" : ""}`}>
          {success ? <Check size={28} /> : error ? <ShieldAlert size={28} /> : <Lock size={28} />}
        </div>

        <h2 className="lock-title">Nhập mật mã bảo mật</h2>
        <p className="lock-subtitle">Cài đặt hệ thống đang được khóa. Vui lòng nhập mã PIN để tiếp tục cấu hình.</p>

        {error && (
          <div className="error-message">
            <ShieldAlert size={14} /> Mật mã không đúng, vui lòng thử lại!
          </div>
        )}

        <div className="pin-dots">
          {[...Array(5)].map((_, i) => (
            <div
              key={i}
              className={`pin-dot ${
                success ? "success" : error ? "error" : i < pin.length ? "filled" : ""
              }`}
            />
          ))}
        </div>

        <div className="keypad">
          {["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((num) => (
            <button key={num} className="keypad-btn" onClick={() => handleKeyPress(num)}>
              {num}
            </button>
          ))}
          <button className="keypad-btn action-btn" onClick={handleClear}>
            Xóa
          </button>
          <button className="keypad-btn" onClick={() => handleKeyPress("0")}>
            0
          </button>
          <button className="keypad-btn action-btn" onClick={handleBackspace}>
            ←
          </button>
        </div>
      </div>
    </div>
  );
};
