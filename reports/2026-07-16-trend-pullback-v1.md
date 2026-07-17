# Trend Pullback v1

> Final status: Reject. The formal 2021-2026 Exness archive Bid/Ask Tick retest produced PF 0.912510, net profit -1,201.49 USD, and maximum equity drawdown 17.666137%. See `2026-07-17-custom-tick-import-and-trend-retest.md`.

Status: `Research - pending long-history real-point retest`

## Hypothesis

When the closed H1 price, EMA(50), and EMA(200) are strictly ordered, an M15 close crossing back over EMA(20) after a pullback has positive continuation expectancy.

## Fixed Rules

- H1 trend: close > EMA50 > EMA200 for long, inverse for short
- M15 pullback recovery across EMA20
- One trade per server day
- Entry window 07:00-20:00 server time
- Force exit at 22:00
- ATR(14) stop at 1.5 ATR
- Take profit at 2R
- Risk 0.25% of equity
- Maximum spread price 0.50

## Aggregate MT5 Result

- Broker: Exness-MT5Real5
- Symbol: XAUUSDm
- Model: Every tick based on real ticks
- Period: M15
- Range: 2025-01-01 to 2026-07-01
- Real ticks: 130,292,930
- Trades: 274
- Net profit: 555.43 USD
- Profit factor: 1.165787
- Expected payoff: 2.027117
- Maximum balance drawdown: 2.896496%
- Maximum equity drawdown: 3.072912%

## Decision

The aggregate baseline passed the minimum research threshold and then completed the following validation without changing its parameters.

## Calendar Validation

### 2025

- Real ticks: 76,058,087
- Trades: 188
- Net profit: 280.97 USD
- Profit factor: 1.116665
- Maximum equity drawdown: 3.072912%

### 2026 H1

- Real ticks: 54,234,843
- Trades: 86
- Net profit: 349.11 USD
- Profit factor: 1.381050
- Maximum equity drawdown: 1.051878%

Both calendar segments retain positive expectancy with the exact baseline parameters.

## Parameter Neighborhood

Ten one-parameter variations were tested over the full 130,292,930 real-tick range. Every variation remained profitable. Profit factor ranged from 1.088646 to 1.242682. This supports a broad parameter neighborhood rather than a single isolated optimum.

No higher-performing variant replaces the baseline. The original 50/200/20 EMA, 1.5 ATR stop, and 2R configuration remains frozen to avoid selection bias.

## Execution Stress

MT5 random execution delay result:

- Trades: 274
- Net profit: 527.32 USD
- Profit factor: 1.155689
- Maximum equity drawdown: 3.210878%

The edge degrades slightly but remains positive.

## Original Decision

The generated-point exploration originally suggested signal-only forward observation.

## Data Quality Correction

Exness `Real5` native real points currently begin at `2026-06-26`. MT5 silently generated earlier points from M1 history for this 2025-2026 H1 run. This report is therefore exploratory and cannot promote the strategy under the required `每个点基于实时点` standard.

The strategy is returned to `Research` until it passes a long-history MT5 custom-symbol test built from external Bid/Ask Tick data and a recent Exness-native calibration test.
