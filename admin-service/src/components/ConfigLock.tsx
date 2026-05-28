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
          background: rgba(10, 10, 12, 0.85);
          backdrop-filter: blur(16px);
          -webkit-backdrop-filter: blur(16px);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 99999;
          font-family: 'Outfit', 'Inter', system-ui, -apple-system, sans-serif;
          color: #f3f4f6;
        }

        .lock-card {
          background: rgba(20, 20, 25, 0.7);
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 24px;
          padding: 40px;
          width: 380px;
          max-width: 90%;
          box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
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
          height: 3px;
          background: linear-gradient(90deg, #3b82f6, #8b5cf6, #ec4899);
        }

        .lock-icon-wrapper {
          width: 64px;
          height: 64px;
          border-radius: 20px;
          background: rgba(59, 130, 246, 0.1);
          border: 1px solid rgba(59, 130, 246, 0.2);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 24px;
          color: #3b82f6;
          transition: all 0.3s ease;
        }

        .lock-icon-wrapper.success {
          background: rgba(16, 185, 129, 0.1);
          border-color: rgba(16, 185, 129, 0.3);
          color: #10b981;
          transform: scale(1.1);
        }

        .lock-icon-wrapper.error {
          background: rgba(239, 68, 68, 0.1);
          border-color: rgba(239, 68, 68, 0.3);
          color: #ef4444;
        }

        .lock-title {
          font-size: 20px;
          font-weight: 700;
          margin-bottom: 8px;
          letter-spacing: -0.025em;
          color: #ffffff;
        }

        .lock-subtitle {
          font-size: 14px;
          color: #9ca3af;
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
          border: 2px solid rgba(255, 255, 255, 0.2);
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .pin-dot.filled {
          background: #ffffff;
          border-color: #ffffff;
          transform: scale(1.15);
          box-shadow: 0 0 12px rgba(255, 255, 255, 0.5);
        }

        .pin-dot.success {
          background: #10b981;
          border-color: #10b981;
          box-shadow: 0 0 12px rgba(16, 185, 129, 0.6);
        }

        .pin-dot.error {
          background: #ef4444;
          border-color: #ef4444;
          box-shadow: 0 0 12px rgba(239, 68, 68, 0.6);
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
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid rgba(255, 255, 255, 0.05);
          color: #f3f4f6;
          font-size: 18px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.15s ease;
          display: flex;
          align-items: center;
          justify-content: center;
          user-select: none;
        }

        .keypad-btn:hover {
          background: rgba(255, 255, 255, 0.08);
          border-color: rgba(255, 255, 255, 0.1);
          transform: translateY(-1px);
        }

        .keypad-btn:active {
          transform: translateY(1px);
          background: rgba(255, 255, 255, 0.12);
        }

        .keypad-btn.action-btn {
          font-size: 13px;
          font-weight: 500;
          color: #9ca3af;
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
          color: #ef4444;
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
