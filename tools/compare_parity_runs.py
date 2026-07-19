#!/usr/bin/env python3
"""Strictly compare automatic and manual MT5 parity artifacts."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_summary(path: pathlib.Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.reader(handle))
    if not rows or rows[0] != ["key", "value"]:
        raise ValueError(f"invalid summary header: {path}")
    return {row[0]: row[1] for row in rows[1:]}


def read_rows(path: pathlib.Path) -> list[list[str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.reader(handle))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    root = pathlib.Path(args.directory).resolve()
    output = pathlib.Path(args.output).resolve()
    result: dict[str, object] = {
        "status": "blocked",
        "gate": "ALIGNMENT BLOCKED",
        "checks": [],
        "missing": [],
    }
    names = ["summary", "daily", "deals"]
    paths = {
        label: {name: root / f"{label}-{name}.csv" for name in names}
        for label in ("auto", "gui")
    }
    missing = [str(path) for group in paths.values() for path in group.values() if not path.exists()]
    if missing:
        result["missing"] = missing
        output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 2

    auto_summary = read_summary(paths["auto"]["summary"])
    gui_summary = read_summary(paths["gui"]["summary"])
    summary_keys = sorted((set(auto_summary) | set(gui_summary)) - {"run_label"})
    summary_differences = [
        {"key": key, "auto": auto_summary.get(key), "gui": gui_summary.get(key)}
        for key in summary_keys
        if auto_summary.get(key) != gui_summary.get(key)
    ]
    checks: list[dict[str, object]] = [
        {
            "name": "summary_fields",
            "passed": not summary_differences,
            "differences": summary_differences,
        }
    ]
    for name in ("daily", "deals"):
        auto_rows = read_rows(paths["auto"][name])
        gui_rows = read_rows(paths["gui"][name])
        differences = []
        for index in range(max(len(auto_rows), len(gui_rows))):
            auto_row = auto_rows[index] if index < len(auto_rows) else None
            gui_row = gui_rows[index] if index < len(gui_rows) else None
            if auto_row != gui_row:
                differences.append({"row": index + 1, "auto": auto_row, "gui": gui_row})
                if len(differences) == 20:
                    break
        checks.append(
            {
                "name": f"{name}_rows",
                "passed": not differences and len(auto_rows) == len(gui_rows),
                "auto_rows": len(auto_rows),
                "gui_rows": len(gui_rows),
                "differences": differences,
            }
        )

    result["checks"] = checks
    result["artifacts"] = {
        label: {
            name: {
                "path": str(path),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for name, path in group.items()
        }
        for label, group in paths.items()
    }
    passed = all(bool(check["passed"]) for check in checks)
    result["status"] = "passed" if passed else "failed"
    result["gate"] = "ALIGNMENT PASSED" if passed else "ALIGNMENT FAILED"
    output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
