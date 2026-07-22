# Project Handoff

## Source of truth

- Git remote: `https://github.com/jimmymen/mt5-exness-gold-tick-lab.git`
- Server project: `C:\QuantResearch\mt5-gold-research`
- Runtime registry: `reports\research-registry.json` on the server
- MT5 data: `%APPDATA%\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`
- Secrets: `C:\ProgramData\MT5GoldResearch`; never copy them into Git or chat

Git contains source and automation. The server contains runtime state, generated
reports, Tick databases, caches, and credentials. A complete handoff needs both.

## Continue from another computer

1. Install Git and an SSH client.
2. Authenticate to the private GitHub repository and clone it.
3. Connect to the Windows server over SSH for operational work. Do not duplicate
   the 249,744,134-Tick database onto the client unless rebuilding an MT5 server.
4. Before editing, compare the local branch with the server and check `git status`.
5. Use Git for reviewed source changes. Use SCP only for deployment and retrieval
   of runtime evidence that is intentionally excluded by `.gitignore`.

Example client commands for an authorized operator:

```bash
git clone https://github.com/jimmymen/mt5-exness-gold-tick-lab.git
ssh <server-user>@<server-host>
```

## Continue with an AI agent

Hermes, OpenCode, or another coding agent should be pointed at the cloned project
and given this file plus `README.md` and `DATASET.md`. The agent also needs SSH
access to the server, but should not receive API keys in prompts.

Non-negotiable controls:

- MQL5/MT5 performs strategy logic, execution, P/L, drawdown, and coverage.
- Formal tests use `XAUUSDm_EXNESS_V2`, `Model=4`, and real Tick evidence.
- Development is `2021.07.02-2024.01.09`; OOS is
  `2024.01.09-2025.04.13`; the locked period must not be tested.
- `InpVolume=0.01`; optimization and live trading stay disabled.
- Every Tick-covered UTC day must have an entry and `missing_days=0`.
- Never commit credentials, terminal logs, Tick files, or generated runtime data.

Before changing production, the agent should inspect:

```powershell
Get-ScheduledTask -TaskName "MT5 Gold Research - AI Worker"
Get-Content C:\QuantResearch\mt5-gold-research\reports\development-state.json -Raw
git -C C:\QuantResearch\mt5-gold-research status --short
```

## Feishu notifications

The supported mode is a Feishu enterprise custom application with bot capability.
Reset any secret that has appeared in chat, ensure the bot is in the target group,
and grant the application permission to send messages and list its chats. Run on
the Windows server desktop:

```powershell
powershell -ExecutionPolicy Bypass -File C:\QuantResearch\mt5-gold-research\scripts\set-feishu-credentials.ps1
```

Enter the App ID, rotated App Secret, and optionally the target `chat_id`
interactively. They are stored in
`C:\ProgramData\MT5GoldResearch\feishu-credentials.json` with access restricted
to `SYSTEM` and `Administrators`.

If the `chat_id` is not known, list the groups visible to the bot and select one:

```powershell
powershell -ExecutionPolicy Bypass -File C:\QuantResearch\mt5-gold-research\scripts\list-feishu-chats.ps1
```

Each completed candidate sends its ID, publication/rejection decision,
development and OOS metrics, daily coverage, and dashboard URL. A Feishu outage
only writes a warning and never changes the MT5 result or stops research.

## Parallel testing status

Production intentionally uses one MT5 Tester slot. A second portable terminal
passed sequential consistency testing, but concurrent access to the shared custom
Tick database failed with Windows file-sharing error 32. Do not enable parallel
slots until the server has enough disk for an independent Tick database and the
two-slot real-Tick test passes again.
