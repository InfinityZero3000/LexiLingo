import React from "react";

export const BentoChartDefs: React.FC = () => (
  <svg
    width={0}
    height={0}
    style={{ position: "absolute", width: 0, height: 0, overflow: "hidden" }}
    aria-hidden="true"
  >
    <defs>
      <linearGradient id="bentoBlueArea" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="#FF4D00" stopOpacity={0.42} />
        <stop offset="100%" stopColor="#FF4D00" stopOpacity={0} />
      </linearGradient>
      <linearGradient id="bentoLimeArea" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="#FF8A3D" stopOpacity={0.36} />
        <stop offset="100%" stopColor="#FF8A3D" stopOpacity={0} />
      </linearGradient>
      <linearGradient id="bentoIndigoArea" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="#FDBA74" stopOpacity={0.32} />
        <stop offset="100%" stopColor="#FDBA74" stopOpacity={0} />
      </linearGradient>
      <linearGradient id="bentoBlueBar" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="#FF6A1A" />
        <stop offset="100%" stopColor="#FF4D00" />
      </linearGradient>
      <linearGradient id="bentoLimeBar" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="#FF9F43" />
        <stop offset="100%" stopColor="#FF7A00" />
      </linearGradient>
      <linearGradient id="bentoSoftBar" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stopColor="#CBD5E1" />
        <stop offset="100%" stopColor="#94A3B8" />
      </linearGradient>
    </defs>
  </svg>
);

export type BentoTooltipPayloadItem = {
  name?: string | number;
  value?: number | string;
  color?: string;
  dataKey?: string | number;
  payload?: Record<string, unknown>;
};

export type BentoTooltipProps = {
  active?: boolean;
  payload?: BentoTooltipPayloadItem[];
  label?: string | number;
  labelFormatter?: (label: string | number) => string;
  valueFormatter?: (
    value: number | string,
    name?: string,
    entryPayload?: Record<string, unknown>
  ) => string;
  dark?: boolean;
};

export const BentoTooltip: React.FC<BentoTooltipProps> = ({
  active,
  payload,
  label,
  labelFormatter,
  valueFormatter,
  dark = true,
}) => {
  if (!active || !payload || payload.length === 0) {
    return null;
  }

  const formattedLabel =
    label !== undefined && label !== null && String(label) !== ""
      ? labelFormatter
        ? labelFormatter(label)
        : String(label)
      : "";

  const containerStyle: React.CSSProperties = dark
    ? {
        background: "rgba(15, 23, 42, 0.94)",
        color: "#F8FAFC",
        border: "1px solid rgba(148, 163, 184, 0.22)",
        boxShadow: "0 14px 32px rgba(15, 23, 42, 0.28)",
      }
    : {
        background: "rgba(255, 255, 255, 0.96)",
        color: "#0F172A",
        border: "1px solid rgba(148, 163, 184, 0.28)",
        boxShadow: "0 14px 32px rgba(15, 23, 42, 0.12)",
      };

  return (
    <div
      className="bento-chart-tooltip"
      style={{
        ...containerStyle,
        borderRadius: 14,
        padding: "10px 14px",
        backdropFilter: "blur(10px)",
        minWidth: 132,
        fontSize: 12,
        lineHeight: 1.4,
      }}
    >
      {formattedLabel ? (
        <div
          style={{
            fontSize: 11,
            fontWeight: 600,
            color: dark ? "#94A3B8" : "#64748B",
            marginBottom: 6,
            letterSpacing: "0.02em",
          }}
        >
          {formattedLabel}
        </div>
      ) : null}
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        {payload.map((entry, idx) => {
          const rawName = entry.name !== undefined ? String(entry.name) : "";
          const rawVal = entry.value ?? 0;
          const displayVal = valueFormatter
            ? valueFormatter(rawVal, rawName, entry.payload)
            : typeof rawVal === "number"
              ? rawVal.toLocaleString()
              : String(rawVal);

          const dotColor =
            entry.color ||
            (typeof entry.payload?.fill === "string" ? entry.payload.fill : "#FF4D00");

          return (
            <div
              key={`${rawName}-${idx}`}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: 12,
              }}
            >
              <span
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 6,
                  color: dark ? "#CBD5E1" : "#475569",
                  fontWeight: 500,
                }}
              >
                <span
                  style={{
                    width: 8,
                    height: 8,
                    borderRadius: "999px",
                    backgroundColor: dotColor,
                    flexShrink: 0,
                  }}
                />
                {rawName}
              </span>
              <span
                style={{
                  fontWeight: 700,
                  color: dark ? "#FFFFFF" : "#0F172A",
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {displayVal}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export type BentoRingGaugeProps = {
  value: number;
  max?: number;
  centerPrimary: string;
  centerSecondary?: string;
  tone?: "blue" | "lime" | "indigo" | "amber";
  dark?: boolean;
  size?: number;
  strokeWidth?: number;
};

const TONE_COLORS: Record<NonNullable<BentoRingGaugeProps["tone"]>, string> = {
  blue: "#FF4D00",
  lime: "#FF7A00",
  indigo: "#FB923C",
  amber: "#F59E0B",
};

export const BentoRingGauge: React.FC<BentoRingGaugeProps> = ({
  value,
  max = 100,
  centerPrimary,
  centerSecondary,
  tone = "blue",
  dark = false,
  size = 96,
  strokeWidth = 10,
}) => {
  const safeMax = max > 0 ? max : 100;
  const ratio = Math.max(0, Math.min(1, value / safeMax));
  const center = size / 2;
  const radius = Math.max(1, center - strokeWidth / 2);
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference * (1 - ratio);
  const strokeColor = dark && tone === "blue" ? "#FF6A1A" : TONE_COLORS[tone];
  const trackColor = dark ? "rgba(255, 255, 255, 0.14)" : "rgba(148, 163, 184, 0.22)";

  return (
    <div
      className={dark ? "bento-ring bento-ring--dark" : "bento-ring"}
      style={{
        position: "relative",
        width: size,
        height: size,
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
      }}
      role="img"
      aria-label={
        centerSecondary ? `${centerPrimary} ${centerSecondary}` : centerPrimary
      }
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke={trackColor}
          strokeWidth={strokeWidth}
        />
        <circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke={strokeColor}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={dashOffset}
          transform={`rotate(-90 ${center} ${center})`}
          style={{ transition: "stroke-dashoffset 0.5s ease" }}
        />
      </svg>
      <div
        className="bento-ring__center"
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
          padding: strokeWidth + 4,
          pointerEvents: "none",
        }}
      >
        <span
          className="bento-ring__primary"
          style={{
            fontSize: Math.max(14, Math.round(size * 0.2)),
            fontWeight: 700,
            lineHeight: 1.1,
            color: dark ? "#FFFFFF" : "var(--panel-ink, #0F172A)",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {centerPrimary}
        </span>
        {centerSecondary ? (
          <span
            className="bento-ring__secondary"
            style={{
              fontSize: Math.max(10, Math.round(size * 0.115)),
              fontWeight: 500,
              lineHeight: 1.2,
              marginTop: 2,
              color: dark ? "rgba(226, 232, 240, 0.72)" : "var(--muted, #64748B)",
            }}
          >
            {centerSecondary}
          </span>
        ) : null}
      </div>
    </div>
  );
};
