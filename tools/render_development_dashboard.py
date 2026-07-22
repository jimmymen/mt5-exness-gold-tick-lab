#!/usr/bin/env python3
"""Render the authenticated Chinese continuous-research dashboard."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import json
import os
import pathlib
import tempfile


def load(path: pathlib.Path, default: dict) -> dict:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return {**default, "load_error": str(error)}


def curve_svg(path: pathlib.Path) -> str:
    if not path.exists():
        return '<div class="muted">暂无资金曲线</div>'
    try:
        with path.open(newline="", encoding="utf-8-sig") as handle:
            rows = list(csv.DictReader(handle))
        values = [float(row["balance"]) for row in rows]
    except (OSError, UnicodeError, csv.Error, KeyError, TypeError, ValueError):
        return '<div class="muted">资金曲线格式错误</div>'
    if len(values) < 2:
        return '<div class="muted">资金曲线数据不足</div>'
    width, height, pad = 760, 220, 18
    low, high = min(values), max(values)
    span = max(high - low, 1.0)
    points = []
    for index, value in enumerate(values):
        x = pad + index * (width - 2 * pad) / (len(values) - 1)
        y = height - pad - (value - low) * (height - 2 * pad) / span
        points.append(f"{x:.1f},{y:.1f}")
    return (
        f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="资金曲线">'
        f'<line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" class="axis"/>'
        f'<polyline points="{" ".join(points)}" class="curve"/>'
        f'<text x="{pad}" y="14" class="chart-label">最高 {high:,.2f}</text>'
        f'<text x="{pad}" y="{height-3}" class="chart-label">最低 {low:,.2f}</text></svg>'
    )


def duration_text(start: object, finish: object) -> str:
    try:
        started = dt.datetime.fromisoformat(str(start).replace("Z", "+00:00"))
        finished = dt.datetime.fromisoformat(str(finish).replace("Z", "+00:00"))
        seconds = max(0, int((finished - started).total_seconds()))
    except (TypeError, ValueError):
        return "旧记录未单独统计"
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours}小时{minutes}分{seconds}秒" if hours else f"{minutes}分{seconds}秒"


def strategy_cards(registry: dict, reports: pathlib.Path, badge: str = "合格盈利策略") -> str:
    published = registry.get("published", [])[-20:]
    evaluation_ids = {str(item.get("id")) for item in registry.get("evaluations", [])}
    if not published:
        return '<div class="empty">尚无达到发布条件的盈利策略</div>'
    cards = []
    for item in reversed(published):
        name = html.escape(str(item["name"]))
        chinese_name = html.escape(str(item.get("chinese_name", name)))
        explanation = html.escape(str(item.get("explanation_zh", "暂无中文说明")))
        source = html.escape(str(item["source_url"]))
        trace = (
            f'<a class="trace" href="#generation-{name}">查看AI研发路径</a>'
            if str(item["name"]) in evaluation_ids
            else ""
        )
        curve = curve_svg(reports / str(item["curve_file"]))
        oos_curve = (
            curve_svg(reports / str(item["oos_curve_file"]))
            if item.get("oos_curve_file")
            else '<div class="muted">旧规则没有独立样本外曲线</div>'
        )
        coverage = (
            f"{int(item['covered_days'])}/{int(item['active_days'])}"
            if item.get("active_days") is not None
            else "旧规则未统计"
        )
        published_utc = str(item.get("published_utc", ""))
        track_new = "true" if badge == "合格盈利策略" else "false"
        development_started = item.get("development_started_utc")
        development_finished = item.get("development_finished_utc")
        oos_started = item.get("oos_started_utc")
        oos_finished = item.get("oos_finished_utc")
        development_duration = duration_text(development_started, development_finished)
        oos_duration = duration_text(oos_started, oos_finished)
        cards.append(f"""
<details class="strategy" data-strategy-id="{name}" data-published="{html.escape(published_utc)}" data-track-new="{track_new}">
<summary><span><span class="eyebrow">{html.escape(badge)}</span><strong>{chinese_name}</strong> <code>{name}</code></span>
<span class="summary-metric">开发区 +{float(item['profit']):,.2f} · 样本外 {float(item.get('oos_profit',0)):,.2f} USD</span></summary>
<div class="strategy-body"><div class="strategy-head"><div><h3>{chinese_name}</h3><code>{name}</code></div><div class="actions">{trace}<a class="download" href="{source}">下载 MQL5 源码</a></div></div>
<p class="explain">{explanation}</p><div class="metrics">
<div><span>净利润</span><strong class="positive">+{float(item['profit']):,.2f} USD</strong></div>
<div><span>盈利因子</span><strong>{float(item['profit_factor']):.3f}</strong></div>
<div><span>交易数</span><strong>{int(item['trades'])}</strong></div>
<div><span>交易日覆盖</span><strong>{coverage}</strong></div>
<div><span>最大权益回撤</span><strong>{float(item['equity_dd_pct']):.2f}%</strong></div>
<div><span>测试区间</span><strong>{html.escape(str(item['period']))}</strong></div>
<div><span>真实 Tick</span><strong>{int(item['ticks']):,}</strong></div></div>
<div class="times"><div><span>规格生成</span><code>{html.escape(str(item.get('generated_utc','旧规则未记录')))}</code></div>
<div><span>回测开始</span><code>{html.escape(str(item.get('backtest_started_utc','旧规则未记录')))}</code></div>
<div><span>回测结束</span><code>{html.escape(str(item.get('backtest_finished_utc','旧规则未记录')))}</code></div>
<div><span>看板发布</span><code>{html.escape(str(item.get('published_utc','旧规则未记录')))}</code></div></div>
<h4>开发区资金曲线</h4><div class="chart">{curve}</div>
<div class="curve-time"><span>测试期间：{html.escape(str(item.get('period','未知')))}</span><span>回测开始：{html.escape(str(development_started or '旧记录未记录'))}</span><span>回测结束：{html.escape(str(development_finished or '旧记录未记录'))}</span><strong>实际用时：{development_duration}</strong></div>
<h4>样本外结果</h4><div class="metrics"><div><span>期间</span><strong>{html.escape(str(item.get('oos_period','旧规则未划分')))}</strong></div>
<div><span>净利润</span><strong>{float(item.get('oos_profit',0)):,.2f} USD</strong></div>
<div><span>盈利因子</span><strong>{float(item.get('oos_profit_factor',0)):.3f}</strong></div>
<div><span>交易数</span><strong>{int(item.get('oos_trades',0))}</strong></div>
<div><span>交易日覆盖</span><strong>{int(item.get('oos_covered_days',0))}/{int(item.get('oos_active_days',0))}</strong></div></div>
<div class="chart">{oos_curve}</div>
<div class="curve-time"><span>测试期间：{html.escape(str(item.get('oos_period','旧规则未划分')))}</span><span>回测开始：{html.escape(str(oos_started or '旧记录仅保存总回测时间'))}</span><span>回测结束：{html.escape(str(oos_finished or '旧记录仅保存总回测时间'))}</span><strong>实际用时：{oos_duration}</strong></div>
<p class="blind"><strong>盲区：</strong>{html.escape(str(item.get('blind_period','旧结果曾使用完整期间，不能视为盲测')))}</p></div></details>""")
    return "".join(cards)


def archived_strategy_rows(registry: dict) -> str:
    archived = registry.get("published", [])[:-20]
    if not archived:
        return '<div class="muted">暂无已回收的旧盈利策略</div>'
    rows = "".join(
        f"<tr><td><code>{html.escape(str(item.get('name')))}</code></td>"
        f"<td>{html.escape(str(item.get('chinese_name','')))}</td>"
        f"<td>{float(item.get('profit',0)):,.2f}</td>"
        f"<td>{float(item.get('oos_profit',0)):,.2f}</td>"
        f"<td>{html.escape(str(item.get('published_utc','')))}</td></tr>"
        for item in reversed(archived)
    )
    return (
        f'<details class="archive"><summary>已回收旧盈利策略 {len(archived)} 个（不加载资金曲线）</summary>'
        f'<div class="archive-scroll"><table><thead><tr><th>ID</th><th>名称</th><th>开发区利润</th>'
        f'<th>样本外利润</th><th>发布时间</th></tr></thead><tbody>{rows}</tbody></table></div></details>'
    )


def evaluation_rows(registry: dict) -> str:
    all_evaluations = registry.get("evaluations", [])
    required_ids = {str(item.get("name")) for item in registry.get("published", [])[-20:]}
    recent_ids = {str(item.get("id")) for item in all_evaluations[-12:]}
    evaluations = [
        item for item in all_evaluations
        if str(item.get("id")) in required_ids | recent_ids
    ]
    if not evaluations:
        return '<div class="empty">学习闭环尚未产生新一代评估</div>'
    labels = {
        "PUBLISH": "开发区与样本外通过",
        "REJECT_DEVELOPMENT": "开发区淘汰",
        "REJECT_OOS": "样本外淘汰",
    }
    rows = []
    for item in reversed(evaluations):
        development = item.get("development") or {}
        oos = item.get("oos") or {}
        generation_id = html.escape(str(item.get("id")))
        rows.append(f"""<article class="generation" id="generation-{generation_id}"><div class="generation-head"><div>
<div class="eyebrow">{html.escape(labels.get(str(item.get('decision')), str(item.get('decision'))))}</div>
<h3>{html.escape(str(item.get('id')))}</h3></div><code>父代 {html.escape(str(item.get('parent_id','ROOT')))}</code></div>
<div class="analysis"><div><span>AI失败诊断</span><p>{html.escape(str(item.get('failure_analysis_zh','')))}</p></div>
<div><span>下一代假设</span><p>{html.escape(str(item.get('hypothesis_zh','')))}</p></div>
<div><span>结构变化</span><p>{html.escape(str(item.get('changes_zh','')))}</p></div></div>
<div class="metrics"><div><span>开发区利润</span><strong>{float(development.get('profit',0)):,.2f}</strong></div>
<div><span>开发区PF</span><strong>{float(development.get('profit_factor',0)):.3f}</strong></div>
<div><span>开发区覆盖</span><strong>{int(development.get('covered_days',0))}/{int(development.get('active_days',0))}</strong></div>
<div><span>样本外利润</span><strong>{float(oos.get('profit',0)):,.2f}</strong></div>
<div><span>样本外PF</span><strong>{float(oos.get('profit_factor',0)):.3f}</strong></div>
<div><span>样本外覆盖</span><strong>{int(oos.get('covered_days',0))}/{int(oos.get('active_days',0))}</strong></div></div>
<div class="times"><div><span>生成</span><code>{html.escape(str(item.get('generated_utc','')))}</code></div>
<div><span>回测开始</span><code>{html.escape(str(item.get('backtest_started_utc','')))}</code></div>
<div><span>回测结束</span><code>{html.escape(str(item.get('backtest_finished_utc','')))}</code></div></div></article>""")
    return "".join(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", required=True)
    parser.add_argument("--parity", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--registry")
    args = parser.parse_args()

    output = pathlib.Path(args.output)
    reports = output.parent
    state = load(pathlib.Path(args.state), {"phase": "初始化", "message": "正在启动"})
    parity = load(pathlib.Path(args.parity),
                  {"status": "blocked", "gate": "ALIGNMENT BLOCKED", "checks": []})
    registry = load(pathlib.Path(args.registry) if args.registry else reports / "research-registry.json",
                    {"published": [], "attempted": 0, "rejected": 0})
    state_updated = state.get("updated_utc")
    try:
        heartbeat = dt.datetime.fromisoformat(str(state_updated).replace("Z", "+00:00"))
        heartbeat_age = (dt.datetime.now(dt.timezone.utc) - heartbeat).total_seconds()
    except (TypeError, ValueError):
        heartbeat_age = float("inf")
    translations = {
        "Waiting for a new server AI API key": "等待在服务器配置新的AI接口密钥",
        "Daily AI limit reached; waiting for next UTC day": "今日AI调用上限已达到，等待下一个UTC日期",
        "AI research iteration failed; retrying automatically": "本轮研发失败，稍后自动重试",
        "research": "研发中",
    }
    running = state.get("phase") in {"research", "running"}
    stale = running and heartbeat_age > 300
    color = "#ff655f" if stale or state.get("error") else "#48d597"
    raw_message = str(state.get("message", "等待任务"))
    raw_message = raw_message.replace(
        "waiting for next hourly cycle", "next continuous cycle starts in 10 seconds"
    )
    gate = "研发进程心跳已中断" if stale else translations.get(raw_message, raw_message)
    cards = strategy_cards(registry, reports)
    archive = archived_strategy_rows(registry)
    historical_cards = strategy_cards(
        {"published": registry.get("historical", [])}, reports, "历史低频结果，不满足新规则"
    )
    generations = evaluation_rows(registry)
    updated = html.escape(str(state_updated or "暂无心跳"))
    error = html.escape(str(state.get("error") or "无"))
    attempted = int(registry.get("attempted", 0))
    rejected = int(registry.get("rejected", 0))
    failed = int(registry.get("failed", 0))
    published = len(registry.get("published", []))
    attempted_specs = registry.get("attempted_specs", [])
    latest_generated = attempted_specs[-1].get("generated_utc", "尚无新制度候选") if attempted_specs else "尚无新制度候选"
    parity_status = html.escape(str(parity.get("gate", "ALIGNMENT BLOCKED")))
    parity_note = "用户已接受版本差异并授权继续；对齐证据仍未通过。" if parity.get("status") != "passed" else "自动与GUI证据完全一致。"
    document = f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="30">
<title>黄金策略 24 小时研发看板</title><style>
:root{{--ink:#17201d;--paper:#f2efe6;--panel:#fffdf7;--line:#d7d0bf;--green:#087f5b;--red:#c43d35;--muted:#68736e}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font:15px/1.6 "Noto Sans SC","Microsoft YaHei",system-ui,sans-serif}}
main{{max-width:1180px;margin:auto;padding:34px 22px 70px}}header{{display:flex;justify-content:space-between;gap:20px;align-items:end;border-bottom:2px solid var(--ink);padding-bottom:20px}}
h1{{font:800 clamp(28px,5vw,52px)/1.05 Georgia,"Noto Serif SC",serif;margin:0;letter-spacing:-1px}}h2{{font-size:22px;margin:36px 0 14px}}h3{{font-size:25px;margin:2px 0}}
.eyebrow{{font-size:11px;letter-spacing:2px;text-transform:uppercase;color:var(--green);font-weight:800}}.muted{{color:var(--muted)}}
.status{{margin:24px 0;background:#fff;border-left:7px solid {color};padding:18px 20px;font-size:19px;font-weight:750;box-shadow:0 8px 24px #17201d0b}}
.overview,.metrics{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:1px;background:var(--line);border:1px solid var(--line)}}
.overview>div,.metrics>div{{background:var(--panel);padding:16px}}span{{display:block;color:var(--muted);font-size:12px;margin-bottom:4px}}strong{{font-size:20px}}.positive{{color:var(--green)}}
.strategy{{background:var(--panel);border:1px solid var(--line);margin:16px 0;box-shadow:0 12px 30px #17201d0a}}.strategy>summary{{cursor:pointer;display:flex;justify-content:space-between;gap:18px;align-items:center;padding:18px 22px;list-style:none}}.strategy>summary::-webkit-details-marker{{display:none}}.strategy>summary:before{{content:"＋";font-size:22px;font-weight:800;margin-right:8px}}.strategy[open]>summary:before{{content:"−"}}.strategy>summary>span:first-of-type{{flex:1}}.strategy>summary strong{{font-size:18px}}.summary-metric{{color:var(--green);font-weight:800;white-space:nowrap}}.strategy-body{{padding:0 24px 24px;border-top:1px solid var(--line)}}.strategy-head{{display:flex;justify-content:space-between;gap:18px;align-items:start;margin-top:18px}}
.actions{{display:flex;gap:8px;align-items:center;flex-wrap:wrap}}.download{{background:var(--ink);color:white;text-decoration:none;padding:10px 15px;font-weight:700;white-space:nowrap}}.trace{{border:1px solid var(--ink);color:var(--ink);text-decoration:none;padding:9px 14px;font-weight:700;white-space:nowrap}}.explain{{font-size:16px;max-width:900px}}
.times{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:8px;margin-top:18px}}.times>div{{border-top:1px solid var(--line);padding-top:8px}}h4{{margin:24px 0 8px}}.blind{{background:#fff1d6;border-left:4px solid #d28a00;padding:12px 14px}}.chart{{margin-top:10px;background:#f7f4eb;border:1px solid var(--line);padding:8px}}.curve-time{{display:flex;flex-wrap:wrap;gap:8px 18px;background:#e8ece7;padding:9px 12px;border:1px solid var(--line);border-top:0;font-size:12px}}.curve-time span{{margin:0}}.curve-time strong{{font-size:12px;color:var(--green)}}svg{{width:100%;height:auto;display:block}}.curve{{fill:none;stroke:var(--green);stroke-width:4;stroke-linejoin:round;stroke-linecap:round}}.axis{{stroke:#b9b2a1}}.chart-label{{font-size:12px;fill:#68736e}}
.archive{{background:#e6e2d8;border:1px solid var(--line);margin:16px 0}}.archive>summary{{cursor:pointer;padding:14px 18px;font-weight:800}}.archive-scroll{{overflow:auto;padding:0 12px 12px}}table{{width:100%;border-collapse:collapse;background:#fff}}th,td{{padding:8px;border:1px solid var(--line);text-align:left;white-space:nowrap}}.generation{{background:#eef3ee;border:1px solid #bfcabf;padding:20px;margin:12px 0}}.generation-head{{display:flex;justify-content:space-between;gap:18px}}.analysis{{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px;margin:14px 0}}.analysis>div{{background:#fff;padding:12px;border:1px solid var(--line)}}.analysis p{{margin:4px 0}}.empty{{border:1px dashed var(--line);padding:28px;color:var(--muted)}}code{{font-family:ui-monospace,Consolas,monospace;color:#42504a}}
@media(max-width:650px){{header,.strategy-head{{display:block}}.actions{{margin-top:14px}}.strategy>summary{{display:block}}.summary-metric{{display:block;margin-top:8px;white-space:normal}}main{{padding:24px 14px}}}}
</style></head><body><main><header><div><div class="eyebrow">Exness XAUUSDm · Model=4</div><h1>黄金策略 24 小时研发看板</h1></div>
<div class="muted">自动刷新 · UTC {updated}</div></header><div class="status">{html.escape(gate)}</div>
<section class="overview"><div><span>运行阶段</span><strong>{html.escape(translations.get(str(state.get('phase','等待')), str(state.get('phase','等待'))))}</strong></div>
<div><span>已测试候选</span><strong>{attempted}</strong></div><div><span>已淘汰</span><strong>{rejected}</strong></div>
<div><span>运行失败</span><strong>{failed}</strong></div><div><span>盈利策略</span><strong class="positive">{published}</strong></div><div><span>最近错误</span><strong>{error}</strong></div></section>
<section class="overview"><div><span>最近候选生成时间</span><strong>{html.escape(str(latest_generated))}</strong></div><div><span>候选节奏</span><strong>完成后10秒立即继续</strong></div><div><span>AI模型</span><strong>{html.escape(str(state.get('ai_model','等待Worker更新')))}</strong></div></section>
<section class="overview"><div><span>开发区 50%</span><strong>2021.07.02 - 2024.01.09</strong></div><div><span>样本外 25%</span><strong>2024.01.09 - 2025.04.13</strong></div><div><span>盲区 25%</span><strong>2025.04.13 - 2026.07.17 · 禁止测试</strong></div></section>
<section class="overview"><div><span>GUI/自动对齐证据</span><strong>{parity_status}</strong></div><div><span>当前政策</span><strong>{parity_note}</strong></div></section>
<h2>盈利策略与资金曲线</h2>{cards}
{archive}
<h2>AI代际学习记录</h2>{generations}
<h2>历史低频结果</h2>{historical_cards}
<h2>研发规则</h2><p class="muted">AI 仅生成白名单范围内的策略规格；MQL5由服务器模板生成。每个候选必须零错误零警告编译，并在
<code>XAUUSDm_EXNESS_V2</code>、2021.07.02起、<code>Model=4</code>真实Tick环境回测。每个有Tick的UTC交易日必须至少成功开仓一次，覆盖率100%、缺失0日且净利润大于0才发布。系统不会执行真实交易。</p>
</main><script>
(() => {{
  const cards = [...document.querySelectorAll('.strategy[data-track-new="true"]')];
  const currentIds = cards.map(card => card.dataset.strategyId);
  let known = JSON.parse(localStorage.getItem('mt5-known-strategies') || 'null');
  let openIds = JSON.parse(sessionStorage.getItem('mt5-open-strategies') || '[]');
  if (known === null) {{
    known = currentIds;
    if (currentIds.length) openIds = [currentIds[0]];
  }} else {{
    const newIds = currentIds.filter(id => !known.includes(id));
    openIds = [...new Set([...newIds, ...openIds])];
    known = [...new Set([...currentIds, ...known])];
  }}
  localStorage.setItem('mt5-known-strategies', JSON.stringify(known));
  sessionStorage.setItem('mt5-open-strategies', JSON.stringify(openIds));
  cards.forEach(card => {{
    const id = card.dataset.strategyId;
    card.open = openIds.includes(id);
    card.addEventListener('toggle', () => {{
      let active = JSON.parse(sessionStorage.getItem('mt5-open-strategies') || '[]');
      active = card.open ? [...new Set([...active, id])] : active.filter(value => value !== id);
      sessionStorage.setItem('mt5-open-strategies', JSON.stringify(active));
    }});
  }});
}})();
</script></body></html>"""
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(dir=output.parent, prefix=f".{output.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(document)
            handle.flush()
            os.fsync(handle.fileno())
        pathlib.Path(temporary_name).replace(output)
    except BaseException:
        pathlib.Path(temporary_name).unlink(missing_ok=True)
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
