# MT5 Exness Gold Tick Lab

Auditable MQL5 strategy research and Exness `XAUUSDm` Bid/Ask Tick processing for MetaTrader 5.

## Current status

- Private research repository.
- Canonical MT5 custom symbol: `XAUUSDm_EXNESS_V2`.
- Accepted Tick range: `2021-01-03 23:05:00.971 UTC` through `2026-07-16 14:15:50.276 UTC`.
- Accepted Tick count: `249,744,134`.
- Final data ZIP files are distributed as private GitHub Release assets, not Git objects.
- `TrendPullback` formal real-Tick result: rejected, PF `0.912510`.

## Invariants

- The MQL5 EA is the only strategy implementation.
- 正式验收使用 MT5 `每个点基于实时点`（`Model=4`）。
- Exness `XAUUSDm` data is the initial research baseline.
- Python or other tools may analyze MT5 reports, but do not simulate trades.
- Live trading is never enabled without explicit approval.

## Environment

- Broker server: `Exness-MT5Real5`
- Account mode: Hedging
- Terminal build: 5836
- Terminal: `C:\Program Files\MetaTrader 5\terminal64.exe`
- Data directory: `%APPDATA%\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`

## Data quality

- Exness `XAUUSDm` 原生实时点当前仅从 `2026-06-26` 开始。
- 更早的 Exness M1 历史会被 MT5 自动转换成生成点，不属于正式验收数据。
- 长期正式研究使用自定义品种 `XAUUSDm_EXNESS_V2`。
- 数据源必须标记为 Exness Archive `XAUUSDm` Bid/Ask Tick，不能标记为 `Exness-MT5Real5` 原生历史 Tick。
- 数据保留两处已披露缺口且不插值；详见 `reports/2026-07-17-exness-xauusdm-tick-archive.md`。

## Layout

- `mql5/Experts/GoldResearch/`: EA source code
- `config/`: Strategy Tester configurations
- `scripts/`: Windows automation scripts
- `tools/`: download, normalization, extraction, and verification tools
- `reports/`: archived tester reports

## Dataset

The final dataset is too large for GitHub Git objects. Download the six ZIP files from the private Release and verify them against [`DATASET.md`](DATASET.md).

Each ZIP contains one MT5-importable CSV:

```csv
Date,Time,Bid,Ask,Last,Volume
2021.01.03,23:05:00.971,1909.308,1909.608,0,0
```

Do not commit account logs, credentials, terminal caches, raw Tick files, or generated reports. The repository `.gitignore` excludes these artifacts.
