#!/usr/bin/env python3
"""Download, validate, and normalize Exness XAUUSDm yearly tick archives."""

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
import time
import urllib.error
import urllib.request
import zipfile


BASE_URL = "https://ticks.ex2archive.com/ticks/{symbol}/{year}/Exness_{symbol}_{year}.zip"
YEARS = range(2021, dt.datetime.now(dt.timezone.utc).year + 1)


def save_json(path: pathlib.Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def remote_size(url: str) -> int:
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "MT5-Gold-Research/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return int(response.headers["Content-Length"])


def download(url: str, target: pathlib.Path, expected_size: int, retries: int) -> None:
    part = target.with_suffix(target.suffix + ".part")
    if target.exists() and target.stat().st_size == expected_size:
        return
    if target.exists():
        target.replace(part)

    for attempt in range(1, retries + 1):
        offset = part.stat().st_size if part.exists() else 0
        headers = {"User-Agent": "MT5-Gold-Research/1.0"}
        if offset:
            headers["Range"] = f"bytes={offset}-"
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=180) as response:
                if offset and response.status != 206:
                    offset = 0
                    part.unlink(missing_ok=True)
                mode = "ab" if offset else "wb"
                with part.open(mode) as handle:
                    shutil.copyfileobj(response, handle, length=1024 * 1024)
            if part.stat().st_size != expected_size:
                raise OSError(f"size {part.stat().st_size} != expected {expected_size}")
            os.replace(part, target)
            return
        except (OSError, TimeoutError, urllib.error.URLError) as error:
            if attempt == retries:
                raise RuntimeError(f"download failed after {retries} attempts: {error}") from error
            time.sleep(min(60, attempt * 5))


def parse_timestamp(value: str) -> dt.datetime:
    return dt.datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%fZ").replace(tzinfo=dt.timezone.utc)


def inspect_archive(path: pathlib.Path, year: int, normalized: pathlib.Path | None) -> dict:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)

    with zipfile.ZipFile(path) as archive:
        bad_member = archive.testzip()
        if bad_member:
            raise ValueError(f"CRC failure in {bad_member}")
        members = [item for item in archive.infolist() if not item.is_dir()]
        if len(members) != 1 or not members[0].filename.lower().endswith(".csv"):
            raise ValueError("archive must contain exactly one CSV")

        output = normalized.open("w", newline="", encoding="ascii") if normalized else None
        writer = csv.writer(output, lineterminator="\n") if output else None
        if writer:
            writer.writerow(["Date", "Time", "Bid", "Ask", "Last", "Volume"])

        rows = bad_rows = reverse = same_timestamp = exact_duplicates = 0
        first = last = previous = previous_row = None
        reverse_examples: list[dict] = []
        minimum_spread = float("inf")
        maximum_spread = float("-inf")
        symbols: set[str] = set()
        try:
            raw = archive.open(members[0])
            text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
            reader = csv.reader(text)
            header = next(reader)
            if header != ["Exness", "Symbol", "Timestamp", "Bid", "Ask"]:
                raise ValueError(f"unexpected header: {header!r}")
            for row in reader:
                rows += 1
                if len(row) != 5:
                    bad_rows += 1
                    continue
                try:
                    timestamp = parse_timestamp(row[2])
                    bid = float(row[3])
                    ask = float(row[4])
                except ValueError:
                    bad_rows += 1
                    continue
                if timestamp.year != year:
                    bad_rows += 1
                if previous is not None:
                    if timestamp < previous:
                        reverse += 1
                        if len(reverse_examples) < 20:
                            reverse_examples.append(
                                {
                                    "row": rows,
                                    "previous": previous_row,
                                    "current": row,
                                    "backward_milliseconds": int((previous - timestamp).total_seconds() * 1000),
                                }
                            )
                    same_timestamp += timestamp == previous
                    exact_duplicates += row == previous_row
                if first is None:
                    first = timestamp
                last = timestamp
                previous = timestamp
                previous_row = row
                symbols.add(row[1])
                spread = ask - bid
                minimum_spread = min(minimum_spread, spread)
                maximum_spread = max(maximum_spread, spread)
                if writer:
                    writer.writerow(
                        [
                            timestamp.strftime("%Y.%m.%d"),
                            timestamp.strftime("%H:%M:%S.%f")[:-3],
                            row[3],
                            row[4],
                            "0",
                            "0",
                        ]
                    )
        finally:
            if output:
                output.close()

    if bad_rows:
        if normalized:
            normalized.unlink(missing_ok=True)
        raise ValueError(f"validation failed: bad_rows={bad_rows}")
    return {
        "year": year,
        "archive": str(path),
        "archive_bytes": path.stat().st_size,
        "csv_bytes": members[0].file_size,
        "sha256": digest.hexdigest(),
        "rows": rows,
        "bad_rows": bad_rows,
        "reverse_timestamps": reverse,
        "reverse_examples": reverse_examples,
        "same_timestamps": same_timestamp,
        "exact_adjacent_duplicates": exact_duplicates,
        "symbols": sorted(symbols),
        "first_utc": first.isoformat() if first else None,
        "last_utc": last.isoformat() if last else None,
        "minimum_spread": minimum_spread if rows else None,
        "maximum_spread": maximum_spread if rows else None,
        "normalized": str(normalized) if normalized else None,
        "normalized_bytes": normalized.stat().st_size if normalized else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--symbol", default="XAUUSDm")
    parser.add_argument("--years", nargs="+", type=int, default=list(YEARS))
    parser.add_argument("--retries", type=int, default=10)
    parser.add_argument("--normalize", action="store_true")
    args = parser.parse_args()

    root = pathlib.Path(args.output).resolve()
    archives = root / "archives"
    normalized_root = root / "mt5-import"
    archives.mkdir(parents=True, exist_ok=True)
    if args.normalize:
        normalized_root.mkdir(parents=True, exist_ok=True)
    status_path = root / "status.json"
    manifest_path = root / "manifest.json"
    if manifest_path.exists():
        results = json.loads(manifest_path.read_text(encoding="utf-8"))
    else:
        results = []
    started = dt.datetime.now(dt.timezone.utc).isoformat()

    for index, year in enumerate(args.years, 1):
        url = BASE_URL.format(symbol=args.symbol, year=year)
        target = archives / f"Exness_{args.symbol}_{year}.zip"
        normalized = normalized_root / f"Exness_{args.symbol}_{year}_MT5.csv" if args.normalize else None
        status = {
            "state": "downloading",
            "started_utc": started,
            "updated_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "current_year": year,
            "year_index": index,
            "years_total": len(args.years),
            "completed_years": [item["year"] for item in results],
            "results": results,
        }
        save_json(status_path, status)
        size = remote_size(url)
        download(url, target, size, args.retries)
        status["state"] = "validating"
        status["updated_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save_json(status_path, status)
        result = inspect_archive(target, year, normalized)
        results = [item for item in results if item["year"] != year]
        results.append(result)
        results.sort(key=lambda item: item["year"])
        save_json(manifest_path, results)

    ordered = sorted(results, key=lambda item: item["year"])
    boundaries = []
    for previous, current in zip(ordered, ordered[1:]):
        previous_last = dt.datetime.fromisoformat(previous["last_utc"])
        current_first = dt.datetime.fromisoformat(current["first_utc"])
        boundaries.append(
            {
                "from_year": previous["year"],
                "to_year": current["year"],
                "previous_last_utc": previous["last_utc"],
                "current_first_utc": current["first_utc"],
                "gap_seconds": (current_first - previous_last).total_seconds(),
                "overlap": current_first <= previous_last,
            }
        )
    summary = {
        "symbol": args.symbol,
        "years": [item["year"] for item in ordered],
        "archive_bytes": sum(item["archive_bytes"] for item in results),
        "csv_bytes": sum(item["csv_bytes"] for item in results),
        "rows": sum(item["rows"] for item in results),
        "first_utc": ordered[0]["first_utc"],
        "last_utc": ordered[-1]["last_utc"],
        "boundaries": boundaries,
        "results": results,
    }
    save_json(root / "summary.json", summary)
    save_json(
        status_path,
        {
            "state": "completed",
            "started_utc": started,
            "updated_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "completed_years": args.years,
            "results": results,
        },
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
