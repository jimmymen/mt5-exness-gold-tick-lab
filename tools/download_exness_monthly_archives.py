#!/usr/bin/env python3
"""Download and validate monthly Exness XAUUSDm archives from 2021 onward."""

from __future__ import annotations

import argparse
import concurrent.futures
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


BASE = "https://ticks.ex2archive.com/ticks/{symbol}"


def save_json(path: pathlib.Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def months(start_year: int, today: dt.date):
    year, month = start_year, 1
    while (year, month) <= (today.year, today.month):
        yield year, month
        if month == 12:
            year, month = year + 1, 1
        else:
            month += 1


def get_size(url: str) -> int:
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "MT5-Gold-Research/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return int(response.headers["Content-Length"])


def download(url: str, target: pathlib.Path, retries: int) -> dict:
    expected = get_size(url)
    part = target.with_suffix(target.suffix + ".part")
    if target.exists() and target.stat().st_size == expected:
        return {"url": url, "path": str(target), "bytes": expected, "cached": True}
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
                    part.unlink(missing_ok=True)
                    offset = 0
                with part.open("ab" if offset else "wb") as handle:
                    shutil.copyfileobj(response, handle, length=1024 * 1024)
            if part.stat().st_size != expected:
                raise OSError(f"size {part.stat().st_size} != {expected}")
            os.replace(part, target)
            return {"url": url, "path": str(target), "bytes": expected, "cached": False}
        except (OSError, TimeoutError, urllib.error.URLError) as error:
            if attempt == retries:
                raise RuntimeError(f"{url}: {error}") from error
            time.sleep(min(60, attempt * 5))
    raise AssertionError("unreachable")


def inspect(item: dict) -> dict:
    path = pathlib.Path(item["path"])
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"CRC failure in {bad}")
        members = [member for member in archive.infolist() if not member.is_dir()]
        if len(members) != 1:
            raise ValueError(f"{path} contains {len(members)} files")
        with archive.open(members[0]) as binary:
            text = io.TextIOWrapper(binary, encoding="utf-8-sig", newline="")
            reader = csv.reader(text)
            header = next(reader)
            if header != ["Exness", "Symbol", "Timestamp", "Bid", "Ask"]:
                raise ValueError(f"unexpected header in {path}: {header!r}")
            rows = 0
            first = last = None
            for row in reader:
                rows += 1
                if len(row) != 5:
                    raise ValueError(f"bad row {rows} in {path}")
                if first is None:
                    first = row
                last = row
    return {
        **item,
        "sha256": digest,
        "csv_bytes": members[0].file_size,
        "rows": rows,
        "first": first,
        "last": last,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--symbol", default="XAUUSDm")
    parser.add_argument("--start-year", type=int, default=2021)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--retries", type=int, default=10)
    args = parser.parse_args()

    root = pathlib.Path(args.output).resolve()
    root.mkdir(parents=True, exist_ok=True)
    today = dt.datetime.now(dt.timezone.utc).date()
    requests = []
    for year, month in months(args.start_year, today):
        name = f"Exness_{args.symbol}_{year}_{month:02d}.zip"
        url = f"{BASE.format(symbol=args.symbol)}/{year}/{month:02d}/{name}"
        requests.append((url, root / name))
    current_name = f"Exness_{args.symbol}_{today.year}_{today.month:02d}_{today.day:02d}.zip"
    current_url = (
        f"{BASE.format(symbol=args.symbol)}/{today.year}/{today.month:02d}/{today.day:02d}/{current_name}"
    )
    requests.append((current_url, root / current_name))

    downloaded = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [executor.submit(download, url, path, args.retries) for url, path in requests]
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            downloaded.append(future.result())
            save_json(
                root.parent / "monthly-status.json",
                {"state": "downloading", "files_completed": index, "files_total": len(futures)},
            )

    results = []
    for index, item in enumerate(sorted(downloaded, key=lambda value: value["path"]), 1):
        results.append(inspect(item))
        save_json(
            root.parent / "monthly-status.json",
            {"state": "validating", "files_completed": index, "files_total": len(downloaded)},
        )
        save_json(root.parent / "monthly-manifest.json", results)
    save_json(
        root.parent / "monthly-status.json",
        {
            "state": "completed",
            "files": len(results),
            "archive_bytes": sum(item["bytes"] for item in results),
            "csv_bytes": sum(item["csv_bytes"] for item in results),
            "rows": sum(item["rows"] for item in results),
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
