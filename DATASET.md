# Exness XAUUSDm Dataset

## Release

The private GitHub Release `ticks-2021-2026-07-16` contains the six final MT5 import archives. GitHub Release assets are used because every file exceeds GitHub's 100 MiB Git object limit.

## Coverage

- Source: Exness archive `XAUUSDm` monthly and current-day files.
- Timezone: UTC.
- Range: `2021-01-03 23:05:00.971` through `2026-07-16 14:15:50.276`.
- Source rows: 250,016,605.
- Exact duplicates removed: 272,471.
- Final Tick rows: 249,744,134.
- MT5 custom symbol: `XAUUSDm_EXNESS_V2`.

## Assets

| Asset | Bytes | Tick rows | SHA-256 |
|---|---:|---:|---|
| `Exness_XAUUSDm_2021_MT5_UTC.zip` | 196,911,627 | 22,103,256 | `9d6f397dc8578a3ca8d3f72cc771f04611f8d335273019da8add734d0eb18108` |
| `Exness_XAUUSDm_2022_MT5_UTC.zip` | 241,108,451 | 27,539,454 | `c69a8865f2e15f2214bc2df85b9f47aaa84ae00c81a342b2e16355ee8a520ab8` |
| `Exness_XAUUSDm_2023_MT5_UTC.zip` | 228,548,166 | 26,113,921 | `411ce1c7969a1c21d6d5ac73636500dc99f73d4e2192a08ed30600d944b9d0c8` |
| `Exness_XAUUSDm_2024_MT5_UTC.zip` | 344,941,689 | 39,691,287 | `321213a9deec28a11eac9db0bff0f6c255316cee1a410833bf39e35d2f9ba22f` |
| `Exness_XAUUSDm_2025_MT5_UTC.zip` | 653,293,775 | 76,215,223 | `5a9aa0fc929453fff906feb9d43d8737c9c9110013334408eb18c6d3ffdf629c` |
| `Exness_XAUUSDm_2026_MT5_UTC.zip` | 514,405,949 | 58,080,993 | `b1d1d4a74fae73eef75ecdecb9f23482139e1ee2008a5d6d3e2100ea579becc8` |

## Known gaps

- `2021-03-02 13:21:24.242 UTC` to `2021-03-04 00:00:00.117 UTC`.
- `2024-04-09 15:02:16.092 UTC` to `2024-04-10 00:00:00.042 UTC`.

The pipeline does not interpolate these gaps or generate synthetic Ticks.

## Validation

- All source and output ZIP CRC checks passed.
- All final SHA-256 checks passed.
- Final output contains zero reverse timestamps.
- MT5 full-database audit counted exactly 249,744,134 Ticks.
- MT5 Strategy Tester logged `generating based on real ticks` without `every tick generation used`.

Detailed evidence:

- [`reports/2026-07-17-exness-xauusdm-tick-archive.md`](reports/2026-07-17-exness-xauusdm-tick-archive.md)
- [`reports/2026-07-17-custom-tick-import-and-trend-retest.md`](reports/2026-07-17-custom-tick-import-and-trend-retest.md)

## Classification

The files are **Exness Archive XAUUSDm Bid/Ask Tick** data. They must not be described as native historical Ticks from the specific `Exness-MT5Real5` account server.
