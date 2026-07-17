# Data Quality Correction

## Terminology

The required Chinese MT5 modeling mode is `每个点基于实时点`. MT5's English agent log identifies this mode with `generating based on real ticks`.

## Exness Real5 Availability

`Exness-MT5Real5` currently synchronizes native `XAUUSDm` tick files from 2026-06-26 onward. Earlier M1 history is available, but native real ticks are not.

When an earlier date is requested with `Model=4`, MT5 can silently fall back and log:

```text
real ticks begin from 2026.06.26 00:00:00, every tick generation used
```

The earlier 2025-2026 H1 strategy runs therefore used generated points before 2026-06-26. They remain exploratory evidence only and are not formal tests under the project's required standard.

## Correct Formal Standard

A formal run is valid only if all conditions hold:

1. The requested model is `Model=4`.
2. MT5 logs `generating based on real ticks`.
3. The first native real tick is no later than the requested start date.
4. The log does not contain `every tick generation used` for the run.
5. The actual first and last tick timestamps cover the requested interval.

## Long-History Plan

Dukascopy `XAUUSD` Bid/Ask tick archives have been verified for 2015, 2020, and 2024. They can be imported into an MT5 custom symbol for long-history research using the same MQL5 EA. Results must be labeled as external-feed real-point research. Recent Exness native real points remain the final broker-specific calibration and acceptance set.
