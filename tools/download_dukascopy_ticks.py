#!/usr/bin/env python3
"""Download and measure Dukascopy XAUUSD Bid/Ask tick archives."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import datetime as dt
import hashlib
import json
import lzma
import os
import pathlib
import struct
import time
import urllib.error
import urllib.request


BASE_URL = "https://datafeed.dukascopy.com/datafeed"
RECORD = struct.Struct("!IIIff")


def hours(start: dt.datetime, end: dt.datetime):
    current = start
    while current < end:
        yield current
        current += dt.timedelta(hours=1)


def url_for(symbol: str, value: dt.datetime) -> str:
    return (
        f"{BASE_URL}/{symbol}/{value.year}/{value.month - 1:02d}/"
        f"{value.day:02d}/{value.hour:02d}h_ticks.bi5"
    )


def target_for(root: pathlib.Path, value: dt.datetime) -> pathlib.Path:
    return root / f"{value.year}" / f"{value.month:02d}" / f"{value.day:02d}" / f"{value.hour:02d}.bi5"


def download_one(symbol: str, root: pathlib.Path, value: dt.datetime, retries: int) -> dict:
    target = target_for(root, value)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size > 0:
        return {"time": value, "path": target, "cached": True}

    url = url_for(symbol, value)
    temporary = target.with_suffix(".part")
    for attempt in range(1, retries + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "MT5-Gold-Research/1.0"})
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = response.read()
            temporary.write_bytes(payload)
            os.replace(temporary, target)
            return {"time": value, "path": target, "cached": False}
        except (OSError, urllib.error.URLError) as error:
            temporary.unlink(missing_ok=True)
            if attempt == retries:
                return {"time": value, "path": target, "error": str(error)}
            time.sleep(attempt * 2)
    raise AssertionError("unreachable")


def inspect_one(result: dict) -> dict:
    value = result["time"]
    path = result["path"]
    if "error" in result:
        return {"time": value.isoformat(), "error": result["error"]}

    compressed = path.read_bytes()
    if not compressed:
        return {
            "time": value.isoformat(),
            "path": str(path),
            "compressed_bytes": 0,
            "raw_bytes": 0,
            "ticks": 0,
            "cached": result["cached"],
        }
    try:
        raw = lzma.decompress(compressed)
    except lzma.LZMAError as error:
        return {"time": value.isoformat(), "path": str(path), "error": f"LZMA: {error}"}
    if len(raw) % RECORD.size != 0:
        return {"time": value.isoformat(), "path": str(path), "error": "raw size is not a multiple of 20"}

    first = RECORD.unpack_from(raw, 0) if raw else None
    last = RECORD.unpack_from(raw, len(raw) - RECORD.size) if raw else None
    return {
        "time": value.isoformat(),
        "path": str(path),
        "compressed_bytes": len(compressed),
        "raw_bytes": len(raw),
        "ticks": len(raw) // RECORD.size,
        "first_millisecond": first[0] if first else None,
        "last_millisecond": last[0] if last else None,
        "sha256": hashlib.sha256(compressed).hexdigest(),
        "cached": result["cached"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbol", default="XAUUSD")
    parser.add_argument("--start", required=True, help="UTC start, YYYY-MM-DD")
    parser.add_argument("--end", required=True, help="UTC exclusive end, YYYY-MM-DD")
    parser.add_argument("--output", required=True)
    parser.add_argument("--workers", type=int, default=32)
    parser.add_argument("--retries", type=int, default=4)
    args = parser.parse_args()

    start = dt.datetime.strptime(args.start, "%Y-%m-%d")
    end = dt.datetime.strptime(args.end, "%Y-%m-%d")
    if end <= start:
        parser.error("end must be after start")

    root = pathlib.Path(args.output).resolve()
    root.mkdir(parents=True, exist_ok=True)
    requested = list(hours(start, end))
    started = time.monotonic()
    downloaded: list[dict] = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [
            executor.submit(download_one, args.symbol, root, value, args.retries)
            for value in requested
        ]
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            downloaded.append(future.result())
            if index % 50 == 0 or index == len(futures):
                elapsed = time.monotonic() - started
                print(f"downloaded {index}/{len(futures)} in {elapsed:.1f}s", flush=True)

    inspected = sorted((inspect_one(item) for item in downloaded), key=lambda item: item["time"])
    errors = [item for item in inspected if "error" in item]
    summary = {
        "symbol": args.symbol,
        "start": args.start,
        "end_exclusive": args.end,
        "hours_requested": len(requested),
        "files_valid": len(inspected) - len(errors),
        "files_with_ticks": sum(1 for item in inspected if item.get("ticks", 0) > 0),
        "errors": len(errors),
        "compressed_bytes": sum(item.get("compressed_bytes", 0) for item in inspected),
        "raw_bytes": sum(item.get("raw_bytes", 0) for item in inspected),
        "ticks": sum(item.get("ticks", 0) for item in inspected),
        "estimated_mqltick_bytes_64": sum(item.get("ticks", 0) for item in inspected) * 64,
        "elapsed_seconds": round(time.monotonic() - started, 3),
    }
    (root / "manifest.json").write_text(json.dumps(inspected, indent=2), encoding="utf-8")
    (root / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    with (root / "errors.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["time", "path", "error"], extrasaction="ignore")
        writer.writeheader()
        writer.writerows(errors)

    print(json.dumps(summary, indent=2), flush=True)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
