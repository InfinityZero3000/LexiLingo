import React from "react";

export const StatusPill = ({
  tone,
  label
}: {
  tone: "success" | "warning" | "info" | "danger" | "neutral";
  label: string;
}) => <span className={`status-pill ${tone}`}>{label}</span>;
