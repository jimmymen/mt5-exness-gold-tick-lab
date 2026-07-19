#!/usr/bin/env python3
"""Render the local continuous-development status dashboard."""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import pathlib


def load(path: pathlib.Path, default: dict) -> dict:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", required=True)
    parser.add_argument("--parity", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    state = load(pathlib.Path(args.state), {"phase": "alignment", "message": "Initializing"})
    parity = load(
        pathlib.Path(args.parity),
        {"status": "blocked", "gate": "ALIGNMENT BLOCKED", "checks": [], "missing": []},
    )
    status = parity.get("status", "blocked")
    color = {"passed": "#52d273", "failed": "#ff5f56", "blocked": "#f4bf4f"}.get(status, "#f4bf4f")
    checks = parity.get("checks", [])
    check_rows = "".join(
        f"<tr><td>{html.escape(str(item.get('name')))}</td>"
        f"<td class={'ok' if item.get('passed') else 'bad'}>{'PASS' if item.get('passed') else 'FAIL'}</td>"
        f"<td>{len(item.get('differences', []))}</td></tr>"
        for item in checks
    ) or '<tr><td colspan="3">Waiting for GUI artifacts</td></tr>'
    missing = parity.get("missing", [])
    missing_html = "".join(f"<li><code>{html.escape(path)}</code></li>" for path in missing)
    gate = html.escape(str(parity.get("gate", "ALIGNMENT BLOCKED")))
    phase = html.escape(str(state.get("phase", "alignment")))
    message = html.escape(str(state.get("message", "Waiting")))
    updated = dt.datetime.now(dt.timezone.utc).isoformat()
    document = f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="10"><title>MT5 Continuous Research</title>
<style>
:root{{--bg:#101318;--panel:#181d25;--line:#303846;--text:#ecf2fa;--muted:#94a3b8;--ok:#52d273;--bad:#ff5f56;--warn:#f4bf4f}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace}}
main{{max-width:1100px;margin:auto;padding:28px}}header{{display:flex;justify-content:space-between;align-items:end;border-bottom:1px solid var(--line);padding-bottom:18px}}
h1{{font:700 30px/1.1 system-ui;margin:0}}.muted{{color:var(--muted)}}.gate{{margin:24px 0;padding:22px;border:1px solid {color};background:{color}18;color:{color};font-size:26px;font-weight:800}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}}.card{{background:var(--panel);border:1px solid var(--line);padding:16px}}
.label{{color:var(--muted);font-size:12px;text-transform:uppercase}}.value{{font-size:20px;margin-top:5px}}table{{width:100%;border-collapse:collapse;background:var(--panel)}}th,td{{border:1px solid var(--line);padding:10px;text-align:left}}th{{color:var(--muted)}}.ok{{color:var(--ok)}}.bad{{color:var(--bad)}}code{{color:#9dd7ff}}ul{{padding-left:20px}}
</style></head><body><main><header><div><h1>MT5 连续研发控制台</h1><div class="muted">Alignment first. Development is blocked until parity passes.</div></div><div class="muted">UTC {html.escape(updated)}</div></header>
<div class="gate">{gate}</div><div class="grid"><div class="card"><div class="label">Current phase</div><div class="value">{phase}</div></div>
<div class="card"><div class="label">Worker state</div><div class="value">{message}</div></div><div class="card"><div class="label">Alignment symbol</div><div class="value">XAUUSDm</div></div>
<div class="card"><div class="label">Formal mode</div><div class="value">Model=4</div></div></div>
<h2>对齐检查</h2><table><thead><tr><th>Layer</th><th>Status</th><th>Differences</th></tr></thead><tbody>{check_rows}</tbody></table>
<h2>等待的 GUI 产物</h2><ul>{missing_html or '<li>None</li>'}</ul>
<h2>GUI 对齐操作</h2><ol>
<li>打开 MT5 策略测试器，EA选择 <code>GoldResearch\\ParityHarness</code>。</li>
<li>品种选择原始 <code>XAUUSDm</code>，周期选择 <code>M1</code>。</li>
<li>模式选择 <code>每个点基于实时点</code>，日期设为 <code>2026.07.13</code> 至 <code>2026.07.17</code>。</li>
<li>关闭优化，执行延迟选择“无延迟”，入金 <code>10000 USD</code>，杠杆 <code>1:100</code>。</li>
<li>加载 <code>parity-gui.set</code>，确认 <code>InpRunLabel=gui</code> 后运行。</li>
<li>无需导出HTML；EA会自动生成 gui-summary、gui-daily、gui-deals，Worker会在30秒内自动比较并更新本页。</li>
</ol>
<h2>研发闸门</h2><p class="muted">只有 summary、daily Tick fingerprints、deals 三层完全一致，连续策略开发 Worker 才允许启动。页面每10秒刷新。</p>
</main></body></html>"""
    pathlib.Path(args.output).write_text(document, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
