// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { DataTable, sortRows, type Column } from "./DataTable";

afterEach(cleanup);

describe("sortRows", () => {
  const rows = [{ n: "b2" }, { n: "a10" }, { n: "a2" }, { n: null }, { n: "" }];

  it("sorts text with numeric awareness and keeps empty values last", () => {
    expect(sortRows(rows, (r) => r.n, "asc").map((r) => r.n)).toEqual(["a2", "a10", "b2", null, ""]);
  });

  it("keeps empty values last when descending", () => {
    expect(sortRows(rows, (r) => r.n, "desc").map((r) => r.n)).toEqual(["b2", "a10", "a2", null, ""]);
  });

  it("compares numbers as numbers, not strings", () => {
    const out = sortRows([{ v: 10 }, { v: 9 }, { v: 100 }], (r) => r.v, "asc");
    expect(out.map((r) => r.v)).toEqual([9, 10, 100]);
  });

  it("is stable for equal values and does not mutate its input", () => {
    const input = [{ k: 1, id: "x" }, { k: 1, id: "y" }, { k: 0, id: "z" }];
    const copy = [...input];
    expect(sortRows(input, (r) => r.k, "asc").map((r) => r.id)).toEqual(["z", "x", "y"]);
    expect(input).toEqual(copy);
  });
});

type Row = { name: string; xp: number };
const data: Row[] = [
  { name: "Cam", xp: 30 },
  { name: "An", xp: 10 },
  { name: "Binh", xp: 20 },
];
const names = () => screen.getAllByRole("row").slice(1).map((tr) => tr.querySelector("td")!.textContent);

describe("DataTable client sort", () => {
  const columns: Column<Row>[] = [
    { header: "Name", render: (r) => r.name, sortValue: (r) => r.name },
    { header: "XP", render: (r) => r.xp, sortValue: (r) => r.xp },
    { header: "Plain", render: () => "-" },
  ];

  it("cycles ascending, descending, original order and reports aria-sort", () => {
    render(<DataTable columns={columns} rows={data} />);
    const header = screen.getByRole("columnheader", { name: /Name/ });
    expect(names()).toEqual(["Cam", "An", "Binh"]);
    expect(header.getAttribute("aria-sort")).toBe("none");

    fireEvent.click(screen.getByRole("button", { name: "Name" }));
    expect(names()).toEqual(["An", "Binh", "Cam"]);
    expect(header.getAttribute("aria-sort")).toBe("ascending");

    fireEvent.click(screen.getByRole("button", { name: "Name" }));
    expect(names()).toEqual(["Cam", "Binh", "An"]);
    expect(header.getAttribute("aria-sort")).toBe("descending");

    fireEvent.click(screen.getByRole("button", { name: "Name" }));
    expect(names()).toEqual(["Cam", "An", "Binh"]);
    expect(header.getAttribute("aria-sort")).toBe("none");
  });

  it("sorts by number and leaves columns without sortValue as plain headers", () => {
    render(<DataTable columns={columns} rows={data} />);
    fireEvent.click(screen.getByRole("button", { name: "XP" }));
    expect(names()).toEqual(["An", "Binh", "Cam"]);
    expect(screen.queryByRole("button", { name: "Plain" })).toBeNull();
    expect(screen.getByRole("columnheader", { name: "Plain" }).getAttribute("aria-sort")).toBeNull();
  });
});

describe("DataTable server sort", () => {
  it("reports the key and leaves row order to the caller", () => {
    const onSort = vi.fn();
    const columns: Column<Row>[] = [{ header: "Name", render: (r) => r.name, sortKey: "name" }];
    render(<DataTable columns={columns} rows={data} sort={{ key: "name", dir: "desc" }} onSort={onSort} />);

    expect(screen.getByRole("columnheader", { name: /Name/ }).getAttribute("aria-sort")).toBe("descending");
    fireEvent.click(screen.getByRole("button", { name: "Name" }));
    expect(onSort).toHaveBeenCalledWith("name");
    expect(names()).toEqual(["Cam", "An", "Binh"]);
  });
});
