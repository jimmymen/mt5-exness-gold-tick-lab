#!/usr/bin/env python3
"""Sort, deduplicate, and convert Exness archives to MT5 import CSV files."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import io
import json
import os
import pathlib
import shutil
import zipfile


def save_json(path: pathlib.Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def parse_timestamp(value: str) -> dt.datetime:
    return dt.datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%fZ").replace(tzinfo=dt.timezone.utc)


def source_rows(path: pathlib.Path):
    with zipfile.ZipFile(path) as archive:
        members = [item for item in archive.infolist() if not item.is_dir()]
        if len(members) != 1:
            raise ValueError(f"{path} must contain one file")
        with archive.open(members[0]) as raw:
            text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
            reader = csv.reader(text)
            header = next(reader)
            if header != ["Exness", "Symbol", "Timestamp", "Bid", "Ask"]:
                raise ValueError(f"unexpected header in {path}: {header!r}")
            yield from reader


def bucket_year(sources: list[pathlib.Path], temporary: pathlib.Path, year: int, status_path: pathlib.Path) -> int:
    temporary.mkdir(parents=True, exist_ok=True)
    handles: dict[str, io.TextIOWrapper] = {}
    rows = 0
    try:
        for source in sources:
            for row in source_rows(source):
                rows += 1
                if len(row) != 5 or not row[2].startswith(f"{year:04d}-"):
                    raise ValueError(f"invalid row {rows}: {row!r}")
                day = row[2][:10]
                if day not in handles:
                    handles[day] = (temporary / f"{day}.csv").open("a", newline="", encoding="ascii")
                csv.writer(handles[day], lineterminator="\n").writerow(row[1:])
                if rows % 5_000_000 == 0:
                    save_json(
                        status_path,
                        {"state": "bucketing", "year": year, "source_rows_processed": rows},
                    )
    finally:
        for handle in handles.values():
            handle.close()
    return rows


def clean_year(
    sources: list[pathlib.Path],
    output: pathlib.Path,
    report_path: pathlib.Path,
    temporary: pathlib.Path,
    year: int,
    status_path: pathlib.Path,
) -> dict:
    source_count = bucket_year(sources, temporary, year, status_path)
    days = sorted(temporary.glob("*.csv"))
    output_temporary = output.with_suffix(output.suffix + ".tmp")
    output_temporary.unlink(missing_ok=True)
    output_rows = duplicates_removed = same_timestamp_different_quote = 0
    first = last = previous_timestamp = None
    maximum_gap_seconds = 0.0
    gaps: list[dict] = []
    day_reports = []

    with zipfile.ZipFile(output_temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
        csv_name = f"Exness_XAUUSDm_{year}_MT5_UTC.csv"
        with archive.open(csv_name, "w", force_zip64=True) as binary:
            text = io.TextIOWrapper(binary, encoding="ascii", newline="", write_through=True)
            writer = csv.writer(text, lineterminator="\n")
            writer.writerow(["Date", "Time", "Bid", "Ask", "Last", "Volume"])
            for day_index, day_path in enumerate(days, 1):
                with day_path.open(newline="", encoding="ascii") as handle:
                    rows = list(csv.reader(handle))
                rows.sort(key=lambda row: (row[1], row[2], row[3]))
                day_output = day_duplicates = 0
                previous_row = None
                for row in rows:
                    if row == previous_row:
                        duplicates_removed += 1
                        day_duplicates += 1
                        continue
                    timestamp = parse_timestamp(row[1])
                    if previous_timestamp is not None:
                        gap = (timestamp - previous_timestamp).total_seconds()
                        maximum_gap_seconds = max(maximum_gap_seconds, gap)
                        if gap >= 6 * 3600:
                            gaps.append(
                                {
                                    "from_utc": previous_timestamp.isoformat(),
                                    "to_utc": timestamp.isoformat(),
                                    "seconds": gap,
                                }
                            )
                        if timestamp == previous_timestamp:
                            same_timestamp_different_quote += 1
                    if first is None:
                        first = timestamp
                    last = timestamp
                    previous_timestamp = timestamp
                    previous_row = row
                    writer.writerow(
                        [
                            timestamp.strftime("%Y.%m.%d"),
                            timestamp.strftime("%H:%M:%S.%f")[:-3],
                            row[2],
                            row[3],
                            "0",
                            "0",
                        ]
                    )
                    output_rows += 1
                    day_output += 1
                day_reports.append(
                    {
                        "date": day_path.stem,
                        "source_rows": len(rows),
                        "output_rows": day_output,
                        "duplicates_removed": day_duplicates,
                    }
                )
                save_json(
                    status_path,
                    {
                        "state": "writing",
                        "year": year,
                        "days_completed": day_index,
                        "days_total": len(days),
                        "output_rows": output_rows,
                        "duplicates_removed": duplicates_removed,
                    },
                )
            text.flush()

        report = {
            "year": year,
            "source_archives": [str(source) for source in sources],
            "output_archive": str(output),
            "timezone": "UTC",
            "format": ["Date", "Time", "Bid", "Ask", "Last", "Volume"],
            "source_rows": source_count,
            "output_rows": output_rows,
            "exact_duplicates_removed": duplicates_removed,
            "same_timestamp_different_quote_preserved": same_timestamp_different_quote,
            "first_utc": first.isoformat() if first else None,
            "last_utc": last.isoformat() if last else None,
            "maximum_gap_seconds": maximum_gap_seconds,
            "gaps_at_least_6_hours": gaps,
            "days": day_reports,
        }
        archive.writestr(f"Exness_XAUUSDm_{year}_quality.json", json.dumps(report, indent=2))

    os.replace(output_temporary, output)
    digest = hashlib.sha256()
    with output.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    report["output_archive_bytes"] = output.stat().st_size
    report["output_sha256"] = digest.hexdigest()
    save_json(report_path, report)
    shutil.rmtree(temporary)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--years", nargs="+", type=int, required=True)
    parser.add_argument("--monthly", action="store_true")
    args = parser.parse_args()

    root = pathlib.Path(args.root).resolve()
    archives = root / ("monthly" if args.monthly else "archives")
    suffix = "-monthly" if args.monthly else ""
    output_root = root / f"mt5-import{suffix}"
    reports = root / f"quality{suffix}"
    temporary_root = root / f"working{suffix}"
    output_root.mkdir(parents=True, exist_ok=True)
    reports.mkdir(parents=True, exist_ok=True)
    temporary_root.mkdir(parents=True, exist_ok=True)
    status_path = root / "normalize-status.json"
    results = []

    for index, year in enumerate(args.years, 1):
        if args.monthly:
            sources = sorted(archives.glob(f"Exness_XAUUSDm_{year}_*.zip"))
        else:
            sources = [archives / f"Exness_XAUUSDm_{year}.zip"]
        if not sources:
            raise FileNotFoundError(f"no source archives for {year}")
        output = output_root / f"Exness_XAUUSDm_{year}_MT5_UTC.zip"
        report_path = reports / f"Exness_XAUUSDm_{year}_quality.json"
        if output.exists() and report_path.exists():
            results.append(json.loads(report_path.read_text(encoding="utf-8")))
            continue
        working = temporary_root / str(year)
        if working.exists():
            shutil.rmtree(working)
        save_json(
            status_path,
            {"state": "starting", "year": year, "year_index": index, "years_total": len(args.years)},
        )
        results.append(clean_year(sources, output, report_path, working, year, status_path))

    save_json(root / f"normalize-summary{suffix}.json", results)
    save_json(
        status_path,
        {
            "state": "completed",
            "years": args.years,
            "source_rows": sum(item["source_rows"] for item in results),
            "output_rows": sum(item["output_rows"] for item in results),
            "duplicates_removed": sum(item["exact_duplicates_removed"] for item in results),
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
