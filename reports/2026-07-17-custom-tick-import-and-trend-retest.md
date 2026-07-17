# Custom Tick Import and TrendPullback Retest

## Custom Symbol

- Symbol: `XAUUSDm_EXNESS_V2`
- Source symbol specification: `XAUUSDm` on `Exness-MT5Real5`
- Tick source: Exness archive monthly and current-day files
- Tick timezone: UTC
- Modeling mode: MT5 `Model=4`, every point based on real ticks

## Import Result

- Years imported: 2021, 2022, 2023, 2024, 2025, 2026 through July 16
- Final Tick count: 249,744,134
- Dates containing Ticks: 1,719
- First Tick: `2021-01-03 23:05:00.971 UTC`
- Last Tick: `2026-07-16 14:15:50.276 UTC`
- First Bid/Ask: `1909.308 / 1909.608`
- Last Bid/Ask: `3989.990 / 3990.230`

Each year was extracted from its independently verified MT5 ZIP, imported in approximately 200,000-Tick batches, and read back immediately after every batch. Batches were never split inside a millisecond containing multiple different quotes.

The MT5-side full database audit independently traversed every UTC day and produced:

```text
AUDIT|summary|symbol=XAUUSDm_EXNESS_V2|ticks=249744134|days=1719|first_msc=1609715100971|last_msc=1784211350276|first_bid=1909.30800|first_ask=1909.60800|last_bid=3989.99000|last_ask=3990.23000
```

## Tester Acceptance

The post-import acceptance run covered July 13 through July 16, 2026. Native Agent evidence:

```text
XAUUSDm_EXNESS_V2,M1 (Exness-MT5Real5): generating based on real ticks
PROBE|summary|reason=1|ticks=1145651|first_msc=1783900800009|last_msc=1784211350276|spread_avg=0.2411725560|spread_max=0.7000000000
XAUUSDm_EXNESS_V2,M1: 1145651 ticks, 4990 bars generated
```

The Agent log does not contain `every tick generation used` for this custom-symbol run.

## TrendPullback Formal Retest

- Test interval requested: `2021-01-04` through `2026-07-17`
- Effective tested Ticks: 249,547,819
- M15 bars: 130,310
- Initial deposit: 10,000 USD
- Final balance: 8,798.51 USD
- Net profit: -1,201.49 USD
- Profit factor: 0.912510
- Expected payoff: -1.180246
- Balance drawdown: 17.396780%
- Equity drawdown: 17.666137%
- Trades: 1,018
- Deals: 2,036
- Decision: Reject

Native strategy summary:

```text
TPB|tester_summary|initial=10000.00|balance=8798.51|profit=-1201.49|profit_factor=0.912510|expected_payoff=-1.180246|balance_dd_pct=17.396780|equity_dd_pct=17.666137|trades=1018|deals=2036
```

The test was run twice. Both runs produced exactly the same Tick count, bar count, trade count, balance, profit factor, expected payoff, and drawdown values.

MT5 used January 3 and January 4 as pre-test history, so the tested Tick count is 196,315 lower than the complete imported database. This is expected terminal warm-up behavior, not missing imported data.

## Interpretation

The earlier exploratory TrendPullback result used periods where MT5 silently generated Ticks from M1 history. Its exploratory profit factor of 1.165787 does not survive the long Exness Bid/Ask Tick retest. The strategy has a negative expectancy and materially larger drawdown on the accepted dataset and must not proceed to forward testing or live automation.

The result also validates the data-quality gate: using genuine historical Bid/Ask Tick data changed the strategy decision from a tentative research candidate to a clear rejection.

## Known Source Gaps

The formal dataset retains two non-market-closure gaps rather than synthesizing prices:

- `2021-03-02 13:21:24.242 UTC` to `2021-03-04 00:00:00.117 UTC`
- `2024-04-09 15:02:16.092 UTC` to `2024-04-10 00:00:00.042 UTC`

These gaps are disclosed, but they do not change the rejection: the strategy's profit factor is below one over 1,018 trades and the repeated result is identical.

## Evidence Files

```text
C:\QuantResearch\mt5-gold-research\reports\custom-tick-audit-terminal.log
C:\QuantResearch\mt5-gold-research\reports\EnvironmentProbe-CustomTicks-agent.log
C:\QuantResearch\mt5-gold-research\reports\TrendPullback-CustomTicks-agent.log
C:\QuantResearch\tick-data\exness\XAUUSDm\mt5-full-import-status.json
C:\QuantResearch\tick-data\exness\XAUUSDm\verify-results.json
```

MT5 did not emit an HTML report for the command-line run. The native Agent log and deterministic repeated `OnTester` summary are the authoritative evidence for this result.
