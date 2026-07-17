#!/usr/bin/env python3
"""Extract one UTC day from a normalized MT5 Tick archive."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import pathlib
import zipfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True)
    parser.add_argument("--start-date", required=True, help="UTC date, YYYY.MM.DD")
    parser.add_argument("--end-date", required=True, help="UTC exclusive date, YYYY.MM.DD")
    parser.add_argument("--probe-date", help="UTC date whose row count is written separately")
    parser.add_argument("--expected-output")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    archive_path = pathlib.Path(args.archive).resolve()
    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = 0
    probe_rows = 0
    first = last = None
    with zipfile.ZipFile(archive_path) as archive:
        members = [member for member in archive.infolist() if member.filename.endswith(".csv")]
        if len(members) != 1:
            raise ValueError("archive must contain one CSV")
        with archive.open(members[0]) as binary, output.open("w", newline="", encoding="ascii") as target:
            reader = csv.reader(io.TextIOWrapper(binary, encoding="ascii", newline=""))
            writer = csv.writer(target, lineterminator="\n")
            header = next(reader)
            writer.writerow(header)
            for row in reader:
                if row[0] < args.start_date:
                    continue
                if row[0] >= args.end_date:
                    break
                writer.writerow(row)
                rows += 1
                if row[0] == args.probe_date:
                    probe_rows += 1
                if first is None:
                    first = row
                last = row
    if not rows:
        output.unlink(missing_ok=True)
        raise ValueError(f"no rows found from {args.start_date} to {args.end_date}")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    manifest = {
        "start_date_utc": args.start_date,
        "end_date_utc_exclusive": args.end_date,
        "rows": rows,
        "first": first,
        "last": last,
        "sha256": digest,
        "bytes": output.stat().st_size,
        "probe_date_utc": args.probe_date,
        "probe_rows": probe_rows,
    }
    if args.expected_output:
        if not args.probe_date or probe_rows == 0:
            raise ValueError("probe date must contain rows when expected output is requested")
        expected_output = pathlib.Path(args.expected_output).resolve()
        expected_output.parent.mkdir(parents=True, exist_ok=True)
        expected_output.write_text(f"{probe_rows}\n", encoding="ascii")
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
