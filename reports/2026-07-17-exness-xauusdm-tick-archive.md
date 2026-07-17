# Exness XAUUSDm Tick Archive Report

## Scope

- Requested range: 2021 through the current day.
- Source: `https://ticks.ex2archive.com/ticks/XAUUSDm/`.
- Canonical source set: 67 monthly ZIP files from 2021-01 through 2026-07, plus the current-day 2026-07-16 ZIP.
- Source timezone: UTC, indicated by the `Z` suffix in every source timestamp.
- Symbol: `XAUUSDm`.

The yearly ZIP files were downloaded and inspected first. The 2024, 2025, and 2026 yearly CSV files stop close to the 2 GiB uncompressed boundary and are incomplete. The final dataset therefore uses monthly ZIP files, not yearly ZIP files.

## Final Result

- Source ZIP files: 68.
- Source compressed bytes: 2,326,702,698.
- Source uncompressed CSV bytes: 15,945,718,802.
- Source rows: 250,016,605.
- Exact duplicate rows removed: 272,471.
- Final Tick rows: 249,744,134.
- First Tick: `2021-01-03 23:05:00.971 UTC`.
- Last Tick at download time: `2026-07-16 14:15:50.276 UTC`.
- Invalid rows: 0.
- Final reverse timestamps: 0.
- Final ZIP CRC failures: 0.
- Final SHA-256 mismatches: 0.

Rows with the same millisecond but different Bid or Ask values were preserved. Only rows with identical symbol, timestamp, Bid, and Ask were removed.

## Yearly Outputs

| Year | Source rows | Final rows | Duplicates removed | First UTC | Last UTC | SHA-256 |
|---|---:|---:|---:|---|---|---|
| 2021 | 22,103,256 | 22,103,256 | 0 | 2021-01-03 23:05:00.971 | 2021-12-31 19:58:58.660 | `9d6f397dc8578a3ca8d3f72cc771f04611f8d335273019da8add734d0eb18108` |
| 2022 | 27,539,454 | 27,539,454 | 0 | 2022-01-02 23:05:10.273 | 2022-12-30 21:57:58.723 | `c69a8865f2e15f2214bc2df85b9f47aaa84ae00c81a342b2e16355ee8a520ab8` |
| 2023 | 26,113,921 | 26,113,921 | 0 | 2023-01-02 23:01:01.640 | 2023-12-29 21:57:55.139 | `411ce1c7969a1c21d6d5ac73636500dc99f73d4e2192a08ed30600d944b9d0c8` |
| 2024 | 39,715,935 | 39,691,287 | 24,648 | 2024-01-01 23:05:09.882 | 2024-12-31 21:57:57.766 | `321213a9deec28a11eac9db0bff0f6c255316cee1a410833bf39e35d2f9ba22f` |
| 2025 | 76,283,540 | 76,215,223 | 68,317 | 2025-01-01 23:05:07.737 | 2025-12-31 21:57:58.898 | `5a9aa0fc929453fff906feb9d43d8737c9c9110013334408eb18c6d3ffdf629c` |
| 2026 | 58,260,499 | 58,080,993 | 179,506 | 2026-01-01 23:05:00.141 | 2026-07-16 14:15:50.276 | `b1d1d4a74fae73eef75ecdecb9f23482139e1ee2008a5d6d3e2100ea579becc8` |

The larger 2026 duplicate count includes overlap between the July monthly file and the separately downloaded current-day file. This overlap was expected and removed exactly.

## Missing Ranges

Two non-weekend gaps remain in the source archive:

1. `2021-03-02 13:21:24.242 UTC` to `2021-03-04 00:00:00.117 UTC`, 34 hours 38 minutes 35.875 seconds.
2. `2024-04-09 15:02:16.092 UTC` to `2024-04-10 00:00:00.042 UTC`, 8 hours 57 minutes 43.950 seconds.

Other gaps of six hours or longer align with normal weekend, Good Friday, Christmas, or New Year market closures. The two gaps above are retained in the quality report and must not be represented as complete real-Tick coverage.

The current-day file is necessarily partial. It ended at `2026-07-16 14:15:50.276 UTC` when downloaded. A later refresh can replace or merge that day, with exact deduplication.

## Format

Each final ZIP contains one MT5 Tick import CSV with this header:

```csv
Date,Time,Bid,Ask,Last,Volume
```

Example:

```csv
2021.01.03,23:05:00.971,1909.308,1909.608,0,0
```

- Date format: `YYYY.MM.DD`.
- Time format: `HH:MM:SS.mmm`.
- Timezone: UTC.
- Bid and Ask: original source values without price interpolation.
- Last and Volume: `0`, because this is an OTC Bid/Ask quote stream and the source does not provide exchange Last or volume fields.

## Server Locations

Raw monthly archives:

```text
C:\QuantResearch\tick-data\exness\XAUUSDm\monthly
```

Final MT5 import archives:

```text
C:\QuantResearch\tick-data\exness\XAUUSDm\mt5-import-monthly
```

Per-year quality reports:

```text
C:\QuantResearch\tick-data\exness\XAUUSDm\quality-monthly
```

Machine-readable manifests and verification:

```text
C:\QuantResearch\tick-data\exness\XAUUSDm\monthly-manifest.json
C:\QuantResearch\tick-data\exness\XAUUSDm\normalize-summary-monthly.json
C:\QuantResearch\tick-data\exness\XAUUSDm\verify-results.json
```

## Validation Method

1. Downloaded all monthly archives with resume and retry support.
2. Downloaded the current-day archive separately to include updates after the July monthly package was generated.
3. Checked every source ZIP CRC and required exactly one CSV member.
4. Required the source header `Exness,Symbol,Timestamp,Bid,Ask`.
5. Required every row to contain exactly five fields and `XAUUSDm` timestamps for the expected year.
6. Partitioned rows by UTC date to repair source block ordering without loading a full year into memory.
7. Sorted by timestamp, Bid, and Ask.
8. Removed only exact duplicate Tick rows.
9. Preserved same-millisecond rows when Bid or Ask differed.
10. Wrote MT5 CSV directly into ZIP64 output archives.
11. Ran a separate verifier over every final archive.
12. Recomputed SHA-256, tested ZIP CRC, recounted every row, checked the header, and required zero reverse timestamps.

## Data Classification

These files are Exness archive Tick data for `XAUUSDm`. They are not claimed to be the native Tick cache of the specific `Exness-MT5Real5` account. The custom symbol and reports must identify the source as Exness archive data. A later overlap comparison against native Real5 Tick data will measure server-level differences.
