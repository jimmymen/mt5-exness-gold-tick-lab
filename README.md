# MT5 Exness Gold Tick Lab

Auditable MQL5 strategy research and Exness `XAUUSDm` Bid/Ask Tick processing for MetaTrader 5.

## Current status

- Private research repository.
- Canonical MT5 custom symbol: `XAUUSDm_EXNESS_V2`.
- Accepted Tick range: `2021-01-03 23:05:00.971 UTC` through `2026-07-16 14:15:50.276 UTC`.
- Accepted Tick count: `249,744,134`.
- Final data ZIP files are distributed as private GitHub Release assets, not Git objects.
- `TrendPullback` formal real-Tick result: rejected, PF `0.912510`.
- GUI parity evidence from terminal build 5833 does not match the build 5836 automatic baseline: `12.43 USD` versus `11.48 USD`. The failure remains visible, while a user-approved policy exception allows research to continue.

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

## Alignment gate

Exact GUI/automatic parity has not been achieved. The failed evidence is retained
and displayed separately from the user-approved policy exception that permits
current research to continue.

The parity harness compares three layers:

1. Tester summary fields and Tick boundaries.
2. Per-day Tick counts and integer fingerprints of timestamp, Bid, and Ask.
3. Every deal's millisecond, direction, entry type, volume, price, commission, swap, and profit.

The alignment run uses the original broker symbol `XAUUSDm` inside its native
real-Tick coverage. Long-history research uses `XAUUSDm_EXNESS_V2`.

The Windows dashboard is available at:

```text
http://127.0.0.1:8765/development-dashboard.html
```

An authenticated public HTTPS proxy can be installed with
`scripts/setup-public-dashboard.ps1`. It exposes the dashboard and authenticated
published strategy downloads; generated credentials remain in a restricted
server-local file and must not be committed.

Exact parity remains failed unless all layers pass. See [`reports/parity-alignment-guide.md`](reports/parity-alignment-guide.md).

On 2026-07-19 the user explicitly accepted the observed Build 5833/5836 parity
difference and authorized strategy research to proceed. The parity result remains
recorded as failed evidence; this authorization does not relabel it as an exact
match.

The first fixed-parameter candidate, `LongTrendBreakout`, produced a positive
historical full-period result before the current split policy. See
`reports/2026-07-19-long-trend-breakout-v1.md` for results and limitations.

## Continuous AI research

The Windows server runs `MT5 Gold Research - AI Worker` continuously. It starts
the next candidate ten seconds after the previous result. AI output is limited
to a constrained indicator specification; the server renders a fixed tester-only
MQL5 template and rejects forbidden capabilities,
requires compilation with zero errors and zero warnings, and runs `Model=4` on
`XAUUSDm_EXNESS_V2` from `2021.07.02`. A candidate is published only when net
profit is positive and every UTC day containing Ticks has at least one successful
entry (`missing_days=0`, 100% coverage). The worker never enables live trading.

AI credentials live only in the ACL-restricted server file
`C:\ProgramData\MT5GoldResearch\ai-credentials.json`. Configure a new key from
the server desktop using `配置AI接口.cmd`; never commit or paste the key into a
chat or command line.

The configured AI model is the official `deepseek-v4-pro` endpoint with thinking
enabled and `reasoning_effort=high`.

The current DeepSeek loop is generational rather than a parameter lottery. It
receives recent structured development/OOS evaluations, diagnoses failure,
states a falsifiable hypothesis, cites a parent generation, and proposes changed
signal composition, volatility regime behavior, exit, target, and trailing-stop
logic. The server renders that constrained DSL through a fixed tester-only MQL5
template; AI still cannot execute commands or bypass coverage, split, blind-period,
or live-trading controls.

The fixed chronological split is development `2021.07.02-2024.01.09` (50%),
out-of-sample `2024.01.09-2025.04.13` (25%), and locked blind period
`2025.04.13-2026.07.17` (25%). Automation must never create an INI or Tester run
covering the blind period. The worker starts the next candidate ten seconds after
the prior candidate finishes; there is no hourly throttle.

## Handoff and notifications

See [`HANDOFF.md`](HANDOFF.md) for continuing from another computer or coding
agent and for configuring server-side Feishu result notifications.

The dashboard links to a separate authenticated ranking page in a new browser
tab. It ranks current-policy published strategies by realized-balance curve
quality first and combined development/OOS profit second. Curve quality penalizes
maximum balance drawdown, sustained drawdown pain, consecutive losing closes, and
consecutive loss depth; OOS receives 60% weight. It also penalizes MT5's official
maximum equity drawdown because the curve CSV contains realized balance at closing
deals rather than mark-to-market equity.
