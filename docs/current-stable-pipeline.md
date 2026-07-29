# Current Stable MT5 Strategy Research Pipeline

Date: 2026-07-29

## Canonical provenance

- Repository: `jimmymen/mt5-exness-gold-tick-lab`
- Research symbol: `XAUUSDm_EXNESS_V2`
- Source: Exness `XAUUSDm` Bid/Ask archive tick data
- Do not substitute the native broker symbol `XAUUSDm`.
- Blind period after `2025-04-13` is locked and must not be imported or tested.

## Compact data window

The current server uses only the development and OOS window:

- Development: `2021-07-02` through `2024-01-09`
- OOS: `2024-01-09` through `2025-04-13`
- No blind-period data is imported.

The imported ranges are processed serially, one archive/range at a time. Each range must produce:

```text
IMPORT|summary|source_rows=N|written=N|verified=1
```

Temporary CSV files are deleted after successful import.

## Recovery and preflight

1. Stop research tasks and residual Worker/Runner/MT5 processes when the environment is suspect.
2. Deploy the authenticated repository cleanly.
3. Compile `CustomTickImporter`, `CustomTickAudit`, and `EnvironmentProbe`; require zero errors and generated EX5 files.
4. Use an interactive Windows Scheduled Task for MT5 import, audit, and probe. Direct non-interactive SSH startup can create an idle terminal without loading an EA.
5. Before starting the Worker, run a `Model=4` probe with the `.set` file copied into `MQL5\\Profiles\\Tester`.
6. Require `generating based on real ticks`, no `every tick generation used`, and nonzero ticks/bars.
7. A historical import status JSON or a loaded custom symbol alone is not proof that current MT5 contains usable ticks.

## Production research loop

Exactly one Worker and one Runner are active:

```text
AI specification
  -> fixed EA template render
  -> compile
  -> development Model=4 real-tick backtest
  -> OOS only under the development gate
  -> registry evaluation
  -> Feishu notification
```

Hard constraints:

- Model `4`, every tick based on real ticks;
- initial deposit `100000 USD`;
- minimum volume `0.01`;
- maximum three indicators per candidate;
- development/OOS isolation;
- development-loss candidates do not receive neighborhood tests.

## Result visibility

Every completed evaluation is registered and sent to Feishu, including:

- `REJECT_DEVELOPMENT`;
- `REJECT_OOS`;
- `PUBLISH`.

Development rejects send text plus the development equity curve and explicitly state that OOS was not run. Candidates with OOS results send the available development and OOS evidence. Publication is a status layer, not a visibility filter.

A successful notification must return real Feishu `message_id` values and identify which curve attachments were sent.

## Stability verification

Do not treat Scheduled Task `Running` as proof. Verify:

- live Worker process;
- zero Worker failures;
- current candidate and compile evidence;
- real-tick evidence;
- registry evaluation;
- Feishu message IDs and curve attachment status.

Known pitfalls:

- `Running` or `267009` can be stale while no process exists;
- `.set` files must be copied into the Tester profile;
- Feishu legacy sending expects `user_id` and object `content`;
- never print GitHub, AI, Feishu, or broker credentials;
- revoke a GitHub PAT if it has been pasted into chat.
