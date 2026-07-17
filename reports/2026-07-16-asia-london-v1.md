# Asia-London Breakout v1

Status: `Reject`

## Hypothesis

An M15 close outside the Exness-server-time 00:00-08:00 Asian range continues during 08:00-16:00.

## Fixed Rules

- One trade per day
- ATR(14) stop at 1.0 ATR
- Take profit at 2R
- Force exit at 20:00 server time
- Risk 0.25% of equity
- Maximum spread price 0.50
- No trend filter

## MT5 Result

- Broker: Exness-MT5Real5
- Symbol: XAUUSDm
- Requested model: `每个点基于实时点`; earlier dates were later found to use MT5 generated points
- Period: M15
- Range: 2025-01-01 to 2026-07-01
- Real ticks: 130,292,930
- Trades: 313
- Net profit: -608.83 USD
- Profit factor: 0.866194
- Expected payoff: -1.945144
- Maximum balance drawdown: 6.517571%
- Maximum equity drawdown: 6.563890%

## Decision

The unfiltered breakout has negative expectancy and is rejected. No parameter optimization will be used to rescue it. Version 2 tests one structural hypothesis only: breakouts aligned with the closed H1 price relative to EMA(200).
