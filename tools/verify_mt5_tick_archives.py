#!/usr/bin/env python3
"""Independently verify normalized MT5 tick ZIP files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import pathlib
import zipfile


def save_json(path: pathlib.Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def verify(path: pathlib.Path, expected: dict) -> dict:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    sha256 = digest.hexdigest()
    if sha256 != expected["output_sha256"]:
        raise ValueError(f"SHA-256 mismatch for {path}")

    with zipfile.ZipFile(path) as archive:
        bad_member = archive.testzip()
        if bad_member:
            raise ValueError(f"CRC failure in {bad_member}")
        members = [member for member in archive.infolist() if member.filename.endswith(".csv")]
        if len(members) != 1:
            raise ValueError(f"expected one CSV in {path}")
        with archive.open(members[0]) as binary:
            text = io.TextIOWrapper(binary, encoding="ascii", newline="")
            reader = csv.reader(text)
            header = next(reader)
            if header != ["Date", "Time", "Bid", "Ask", "Last", "Volume"]:
                raise ValueError(f"unexpected header in {path}: {header!r}")
            rows = reverse = 0
            first = last = previous = None
            for row in reader:
                rows += 1
                if len(row) != 6:
                    raise ValueError(f"bad row {rows} in {path}")
                timestamp = f"{row[0]} {row[1]}"
                if previous is not None and timestamp < previous:
                    reverse += 1
                if first is None:
                    first = row
                last = row
                previous = timestamp
    if rows != expected["output_rows"] or reverse:
        raise ValueError(f"verification failed for {path}: rows={rows}, reverse={reverse}")
    return {
        "year": expected["year"],
        "path": str(path),
        "sha256": sha256,
        "zip_crc": "ok",
        "rows": rows,
        "reverse_timestamps": reverse,
        "first": first,
        "last": last,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    root = pathlib.Path(args.root).resolve()
    expected = json.loads((root / "normalize-summary-monthly.json").read_text(encoding="utf-8"))
    status_path = root / "verify-status.json"
    results = []
    for index, item in enumerate(expected, 1):
        path = pathlib.Path(item["output_archive"])
        save_json(
            status_path,
            {
                "state": "verifying",
                "year": item["year"],
                "year_index": index,
                "years_total": len(expected),
                "completed_years": [result["year"] for result in results],
            },
        )
        results.append(verify(path, item))
        save_json(root / "verify-results.json", results)
    save_json(status_path, {"state": "completed", "results": results})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
