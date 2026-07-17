# Asia-London Breakout v2

Status: `Reject`

## Change From v1

Only trade breakouts aligned with the previous closed H1 candle relative to EMA(200). All entry timing, risk, stop, target, session, and spread rules remain unchanged.

## MT5 Result

- Broker: Exness-MT5Real5
- Symbol: XAUUSDm
- Requested model: `每个点基于实时点`; earlier dates were later found to use MT5 generated points
- Period: M15
- Range: 2025-01-01 to 2026-07-01
- Real ticks: 130,292,930
- Trades: 209
- Net profit: -196.41 USD
- Profit factor: 0.935868
- Expected payoff: -0.939761
- Maximum balance drawdown: 4.119839%
- Maximum equity drawdown: 4.303749%

## Decision

The H1 trend filter materially reduces loss and drawdown, but expectancy remains negative. Direct breakout entry remains rejected. Version 3 keeps the trend filter and requires a later M15 retest of the broken Asian boundary before entry.
