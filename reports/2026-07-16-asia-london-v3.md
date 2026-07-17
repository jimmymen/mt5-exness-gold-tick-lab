# Asia-London Breakout v3

Status: `Reject`

## Change From v2

Keep H1 EMA(200) trend alignment, but do not enter on the breakout close. Arm the direction, then require a later M15 candle to touch within 0.50 of the broken Asian boundary and close back outside it.

## MT5 Result

- Broker: Exness-MT5Real5
- Symbol: XAUUSDm
- Requested model: `每个点基于实时点`; earlier dates were later found to use MT5 generated points
- Period: M15
- Range: 2025-01-01 to 2026-07-01
- Real ticks: 130,292,930
- Trades: 168
- Net profit: 5.81 USD
- Profit factor: 1.002427
- Expected payoff: 0.034583
- Maximum balance drawdown: 4.254787%
- Maximum equity drawdown: 4.561228%

## Decision

Retest entry removes the negative expectancy seen in direct entry, but the edge is effectively zero and has no room for execution degradation. The Asia-London breakout direction is closed after three structural tests. Further numeric tuning would create unacceptable overfitting risk. Research moves to a distinct hypothesis: pullback recovery within an established H1 trend.
