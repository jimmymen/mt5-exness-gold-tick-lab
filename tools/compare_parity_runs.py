#!/usr/bin/env python3
"""Strictly compare automatic and manual MT5 parity artifacts."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import pathlib
import tempfile

SUMMARY_KEYS = {
    "run_label", "symbol", "terminal_build", "ticks", "first_msc", "last_msc",
    "initial", "balance", "profit", "profit_factor", "balance_dd_pct",
    "equity_dd_pct", "trades", "deals",
}
ROW_HEADERS = {
    "daily": [
        "day_utc", "ticks", "first_msc", "last_msc", "time_sum_mod",
        "bid_points_sum", "ask_points_sum",
    ],
    "deals": [
        "index", "time_msc", "type", "entry", "volume", "price",
        "commission", "swap", "profit",
    ],
}


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
    summary: dict[str, str] = {}
    for row in rows[1:]:
        if len(row) != 2:
            raise ValueError(f"invalid summary row: {path}: {row!r}")
        if row[0] in summary:
            raise ValueError(f"duplicate summary key: {path}: {row[0]}")
        summary[row[0]] = row[1]
    return summary


def read_rows(path: pathlib.Path, kind: str) -> list[list[str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.reader(handle))
    if not rows or rows[0] != ROW_HEADERS[kind]:
        raise ValueError(f"invalid {kind} header: {path}")
    width = len(ROW_HEADERS[kind])
    if any(len(row) != width for row in rows[1:]):
        raise ValueError(f"invalid {kind} row width: {path}")
    if kind == "daily" and len(rows) < 2:
        raise ValueError(f"empty daily evidence: {path}")
    return rows


def write_json_atomic(path: pathlib.Path, value: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary = pathlib.Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


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
        "generated_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "checks": [],
        "missing": [],
        "errors": [],
    }
    names = ["summary", "daily", "deals"]
    paths = {
        label: {name: root / f"{label}-{name}.csv" for name in names}
        for label in ("auto", "gui")
    }
    missing = [str(path) for group in paths.values() for path in group.values() if not path.exists()]
    if missing:
        result["missing"] = missing
        write_json_atomic(output, result)
        print(json.dumps(result, indent=2))
        return 2

    try:
        auto_summary = read_summary(paths["auto"]["summary"])
        gui_summary = read_summary(paths["gui"]["summary"])
        for label, summary in (("auto", auto_summary), ("gui", gui_summary)):
            missing_keys = SUMMARY_KEYS - set(summary)
            if missing_keys:
                raise ValueError(f"missing {label} summary keys: {sorted(missing_keys)}")
            if summary["run_label"] != label:
                raise ValueError(f"invalid {label} run_label: {summary['run_label']}")
        rows = {
            label: {name: read_rows(paths[label][name], name) for name in ("daily", "deals")}
            for label in ("auto", "gui")
        }
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        result["errors"] = [str(error)]
        write_json_atomic(output, result)
        print(json.dumps(result, indent=2))
        return 2

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
        auto_rows = rows["auto"][name]
        gui_rows = rows["gui"][name]
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
    write_json_atomic(output, result)
    print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
