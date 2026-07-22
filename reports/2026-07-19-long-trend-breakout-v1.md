# LongTrendBreakout V1 Historical Experiment

## Decision

- Status: historical full-period experiment completed before the current split policy.
- This is an in-sample research result, not evidence of future profitability.
- No parameter optimization or second candidate was run after this result.

## Fixed Strategy

- Long-only daily trend breakout.
- Entry: prior daily close above the 200-day EMA and above the preceding 100-day high.
- Exit: prior daily close below the 200-day EMA or preceding 50-day low.
- Protection: initial and rising stop at three daily ATR below the last close.
- Volume: fixed `0.01` lots.
- Tester-only initialization; the EA cannot initialize on a live chart.

## Historical Result

- Symbol: `XAUUSDm_EXNESS_V2`.
- Data: Exness Archive `XAUUSDm` Bid/Ask Ticks.
- Requested interval: `2021-01-04` through `2026-07-17`.
- Modeling: MT5 `Model=4`, every point based on real Ticks.
- Effective tested Ticks: `241,017,920`.
- Daily bars: `1,618`.
- Initial deposit: `10,000.00 USD`.
- Final balance: `11,311.07 USD`.
- Net profit: `1,311.07 USD`.
- Profit factor: `4.541805`.
- Expected payoff: `87.404667 USD`.
- Balance drawdown: `1.310200%`.
- Equity drawdown: `3.749910%`.
- Trades: `15`.
- Deals: `30`.

Native summary:

```text
LTB|tester_summary|initial=10000.00|balance=11311.07|profit=1311.07|profit_factor=4.541805|expected_payoff=87.404667|balance_dd_pct=1.310200|equity_dd_pct=3.749910|trades=15|deals=30
```

The Agent log contains `generating based on real ticks` for the formal run and
does not contain `every tick generation used`.

## Evidence Status

- Native evidence: `reports/LongTrendBreakout-agent.log` on the research server.
- The exact source and preset hashes recorded at test time do not match the
  current files. The exact immutable run artifacts were not retained, so this
  result must not be presented as reproducible from the current checkout.
- The executable full-period INI and runner are intentionally excluded because
  they cover the period later designated as locked.

## Limitations

- Only 15 trades occurred, so the high profit factor has substantial sampling uncertainty.
- The test period includes a strong structural rise in gold and the strategy is long-only.
- No out-of-sample, walk-forward, parameter sensitivity, execution-delay, or native-symbol calibration test was run because the user requested stopping at the first profitable result.
- The user accepted the existing GUI/automatic parity difference; exact parity was not achieved.
- The period includes `2025.04.13-2026.07.17`, which is locked under the newer
  split policy. This result is ineligible for current publication decisions.
