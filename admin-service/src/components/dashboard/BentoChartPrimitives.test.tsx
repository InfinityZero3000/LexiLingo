// @vitest-environment jsdom
import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import {
  BentoChartDefs,
  BentoRingGauge,
  BentoTooltip,
} from "./BentoChartPrimitives";

afterEach(cleanup);

describe("BentoChartDefs", () => {
  it("renders all expected SVG linearGradient definitions", () => {
    const { container } = render(<BentoChartDefs />);
    const svg = container.querySelector("svg");
    expect(svg).toBeTruthy();
    expect(svg?.getAttribute("aria-hidden")).toBe("true");

    const requiredIds = [
      "bentoBlueArea",
      "bentoLimeArea",
      "bentoIndigoArea",
      "bentoBlueBar",
      "bentoLimeBar",
      "bentoSoftBar",
    ];

    for (const id of requiredIds) {
      const grad = container.querySelector(`defs linearGradient#${id}`);
      expect(grad, `Expected linearGradient#${id} to exist`).toBeTruthy();
      expect(grad?.querySelectorAll("stop").length).toBeGreaterThanOrEqual(2);
    }
  });
});

describe("BentoTooltip", () => {
  const samplePayload = [
    { name: "Active Users", value: 12450, color: "#FF4D00" },
    { name: "Completions", value: 890, payload: { fill: "#FF8A3D" } },
  ];

  it("returns null when active is false or omitted", () => {
    const { container: inactiveContainer } = render(
      <BentoTooltip active={false} payload={samplePayload} label="Mon" />
    );
    expect(inactiveContainer.firstChild).toBeNull();

    const { container: omittedContainer } = render(
      <BentoTooltip payload={samplePayload} label="Mon" />
    );
    expect(omittedContainer.firstChild).toBeNull();
  });

  it("returns null when payload is empty or undefined", () => {
    const { container: emptyContainer } = render(
      <BentoTooltip active={true} payload={[]} label="Mon" />
    );
    expect(emptyContainer.firstChild).toBeNull();

    const { container: missingContainer } = render(
      <BentoTooltip active={true} label="Mon" />
    );
    expect(missingContainer.firstChild).toBeNull();
  });

  it("renders label, series names, and default formatted values when active", () => {
    const { container } = render(
      <BentoTooltip active={true} payload={samplePayload} label="2026-11-25" />
    );

    const tooltip = container.querySelector(".bento-chart-tooltip");
    expect(tooltip).toBeTruthy();
    expect(screen.getByText("2026-11-25")).toBeTruthy();
    expect(screen.getByText("Active Users")).toBeTruthy();
    expect(screen.getByText((12450).toLocaleString())).toBeTruthy();
    expect(screen.getByText("Completions")).toBeTruthy();
    expect(screen.getByText("890")).toBeTruthy();
  });

  it("applies custom labelFormatter and valueFormatter and omits empty label", () => {
    render(
      <BentoTooltip
        active={true}
        label="W47"
        labelFormatter={(lbl) => `Week ${lbl}`}
        valueFormatter={(val, name) => `${name}: ${val}%`}
        payload={[{ name: "Retention", value: 84, color: "#FB923C" }]}
        dark={false}
      />
    );

    expect(screen.getByText("Week W47")).toBeTruthy();
    expect(screen.getByText("Retention")).toBeTruthy();
    expect(screen.getByText("Retention: 84%")).toBeTruthy();

    cleanup();
    const { container } = render(
      <BentoTooltip
        active={true}
        label=""
        payload={[{ name: "Status", value: "Healthy" }]}
      />
    );
    expect(screen.queryByText("Week W47")).toBeNull();
    expect(screen.getByText("Status")).toBeTruthy();
    expect(screen.getByText("Healthy")).toBeTruthy();
    expect(container.querySelector(".bento-chart-tooltip")).toBeTruthy();
  });
});

describe("BentoRingGauge", () => {
  it("renders primary center label and optional secondary label", () => {
    render(
      <BentoRingGauge
        value={78}
        centerPrimary="78%"
        centerSecondary="Uptime"
      />
    );

    const gauge = screen.getByRole("img", { name: "78% Uptime" });
    expect(gauge).toBeTruthy();
    expect(gauge.classList.contains("bento-ring")).toBe(true);
    expect(gauge.classList.contains("bento-ring--dark")).toBe(false);
    expect(screen.getByText("78%").classList.contains("bento-ring__primary")).toBe(true);
    expect(screen.getByText("Uptime").classList.contains("bento-ring__secondary")).toBe(true);
  });

  it("omits secondary label when centerSecondary is not provided", () => {
    const { container } = render(
      <BentoRingGauge value={42} centerPrimary="42" />
    );

    expect(screen.getByRole("img", { name: "42" })).toBeTruthy();
    expect(screen.getByText("42")).toBeTruthy();
    expect(container.querySelector(".bento-ring__secondary")).toBeNull();
  });

  it("applies .bento-ring--dark when dark={true}", () => {
    render(
      <BentoRingGauge
        value={95}
        max={100}
        centerPrimary="95%"
        centerSecondary="SLO"
        tone="lime"
        dark={true}
        size={88}
        strokeWidth={9}
      />
    );

    const gauge = screen.getByRole("img", { name: "95% SLO" });
    expect(gauge.classList.contains("bento-ring")).toBe(true);
    expect(gauge.classList.contains("bento-ring--dark")).toBe(true);
  });

  it("clamps gauge ratio between 0 and 1 for dashoffset calculation", () => {
    const { container } = render(
      <BentoRingGauge value={150} max={100} centerPrimary="100%" tone="amber" />
    );
    const circles = container.querySelectorAll("circle");
    expect(circles.length).toBe(2);
    expect(circles[1].getAttribute("stroke-dashoffset")).toBe("0");
  });
});
