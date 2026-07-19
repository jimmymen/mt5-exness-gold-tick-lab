# MT5 GUI Alignment Gate

Continuous strategy development is blocked until a manual MT5 GUI run exactly matches the automatic baseline.

## GUI settings

- Expert Advisor: `GoldResearch\ParityHarness`
- Symbol: `XAUUSDm_EXNESS_V2`
- Period: `M1`
- Modeling: `每个点基于实时点`
- From: `2026.07.13`
- To: `2026.07.17`
- Execution delay: no delay
- Optimization: disabled
- Deposit: `10000 USD`
- Currency: `USD`
- Leverage: `1:100`
- Parameters: load `parity-gui.set`
- Required parameter: `InpRunLabel=gui`

The preset is installed at:

```text
%APPDATA%\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Profiles\Tester\parity-gui.set
```

## Automatic baseline

- Ticks: 1,145,651
- First millisecond: 1,783,900,800,009
- Last millisecond: 1,784,211,350,276
- Trades: 4
- Deals: 8
- Net profit: 11.56 USD
- Final balance: 10,011.56 USD

These numbers are informational only. The gate compares the generated CSV artifacts directly and does not trust manually transcribed values.

## Gate

The EA writes these files to the MT5 Common Files directory:

```text
GoldResearch\Parity\gui-summary.csv
GoldResearch\Parity\gui-daily.csv
GoldResearch\Parity\gui-deals.csv
```

The continuous worker checks every 30 seconds. It compares:

1. Tick counts, first/last milliseconds, terminal build, and Tester statistics.
2. Per-day Tick counts and integer fingerprints of time, Bid, and Ask.
3. Every deal's millisecond, side, entry type, volume, price, commission, swap, and profit.

Development remains blocked unless all three layers pass exactly.
