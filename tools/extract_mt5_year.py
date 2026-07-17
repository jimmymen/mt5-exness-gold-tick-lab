#!/usr/bin/env python3
"""Extract the single MT5 CSV from a verified yearly ZIP archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import zipfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--expected-rows", required=True, type=int)
    args = parser.parse_args()

    archive_path = pathlib.Path(args.archive).resolve()
    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.unlink(missing_ok=True)

    with zipfile.ZipFile(archive_path) as archive:
        bad_member = archive.testzip()
        if bad_member:
            raise ValueError(f"CRC failure in {bad_member}")
        members = [member for member in archive.infolist() if member.filename.endswith(".csv")]
        if len(members) != 1:
            raise ValueError("archive must contain exactly one CSV")
        with archive.open(members[0]) as source, temporary.open("wb") as target:
            shutil.copyfileobj(source, target, length=4 * 1024 * 1024)
    temporary.replace(output)

    digest = hashlib.sha256()
    rows = -1
    first = last = None
    with output.open("rb") as handle:
        header = handle.readline().decode("ascii").rstrip("\r\n")
        if header != "Date,Time,Bid,Ask,Last,Volume":
            raise ValueError(f"unexpected CSV header: {header!r}")
        for line in handle:
            rows += 1
            if first is None:
                first = line.decode("ascii").rstrip("\r\n")
            last = line.decode("ascii").rstrip("\r\n")
    rows += 1
    if rows != args.expected_rows:
        output.unlink(missing_ok=True)
        raise ValueError(f"row count {rows} != expected {args.expected_rows}")
    with output.open("rb") as handle:
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(block)
    manifest = {
        "archive": str(archive_path),
        "output": str(output),
        "rows": rows,
        "bytes": output.stat().st_size,
        "sha256": digest.hexdigest(),
        "first": first,
        "last": last,
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
