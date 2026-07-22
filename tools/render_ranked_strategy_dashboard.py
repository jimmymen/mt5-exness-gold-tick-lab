#!/usr/bin/env python3
"""Rank published strategies by rising-curve quality, then total profit."""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import os
import pathlib
import tempfile


def load_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {"published": [], "load_error": "注册表读取失败"}


def load_balances(path: pathlib.Path) -> list[float]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    balances = [float(row["balance"]) for row in rows]
    if len(balances) < 2 or not all(math.isfinite(value) for value in balances):
        raise ValueError("invalid balance curve")
    return balances


def curve_metrics(values: list[float]) -> dict[str, float | int]:
    peak = values[0]
    drawdowns: list[float] = []
    gains = 0.0
    losses = 0.0
    loss_streak = 0
    max_loss_streak = 0
    loss_run = 0.0
    max_loss_run = 0.0
    for index, value in enumerate(values):
        peak = max(peak, value)
        drawdowns.append(100.0 * (peak - value) / peak if peak > 0 else 0.0)
        if index == 0:
            continue
        change = value - values[index - 1]
        if change >= 0:
            gains += change
            loss_streak = 0
            loss_run = 0.0
        else:
            losses += -change
            loss_streak += 1
            loss_run += -change
            max_loss_streak = max(max_loss_streak, loss_streak)
            max_loss_run = max(max_loss_run, loss_run)
    initial = values[0]
    max_dd = max(drawdowns)
    ulcer = math.sqrt(sum(value * value for value in drawdowns) / len(drawdowns))
    loss_run_pct = 100.0 * max_loss_run / initial if initial > 0 else 100.0
    upward_efficiency = gains / (gains + losses) if gains + losses > 0 else 0.0
    score = max(
        0.0,
        100.0
        - min(35.0, max_dd * 7.0)
        - min(25.0, ulcer * 10.0)
        - min(20.0, max_loss_streak * 4.0)
        - min(20.0, loss_run_pct * 8.0),
    )
    return {
        "score": round(score, 2),
        "max_dd_pct": round(max_dd, 3),
        "ulcer_pct": round(ulcer, 3),
        "max_loss_streak": max_loss_streak,
        "max_loss_run_pct": round(loss_run_pct, 3),
        "upward_efficiency": round(upward_efficiency * 100.0, 2),
    }


def curve_svg(values: list[float]) -> str:
    width, height, pad = 860, 240, 20
    low, high = min(values), max(values)
    span = max(high - low, 1.0)
    points = []
    for index, value in enumerate(values):
        x = pad + index * (width - 2 * pad) / (len(values) - 1)
        y = height - pad - (value - low) * (height - 2 * pad) / span
        points.append(f"{x:.1f},{y:.1f}")
    return (
        f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="已实现余额曲线">'
        f'<line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" class="axis"/>'
        f'<polyline points="{" ".join(points)}" class="curve"/>'
        f'<text x="{pad}" y="15">最高 {high:,.2f}</text>'
        f'<text x="{pad}" y="{height-3}">最低 {low:,.2f}</text></svg>'
    )


def rank_strategies(registry: dict, reports: pathlib.Path) -> tuple[list[dict], int]:
    ranked: list[dict] = []
    invalid = 0
    for item in registry.get("published", []):
        try:
            development = load_balances(reports / str(item["curve_file"]))
            oos = load_balances(reports / str(item["oos_curve_file"]))
            development_metrics = curve_metrics(development)
            oos_metrics = curve_metrics(oos)
            official_equity_dd = (
                float(item.get("equity_dd_pct", 0.0)) * 0.4
                + float(item.get("oos_equity_dd_pct", 0.0)) * 0.6
            )
            quality = round(
                float(development_metrics["score"]) * 0.4
                + float(oos_metrics["score"]) * 0.6,
                2,
            )
            quality = round(max(0.0, quality - min(20.0, official_equity_dd * 2.0)), 2)
            total_profit = float(item["profit"]) + float(item["oos_profit"])
            ranked.append({
                "item": item,
                "development": development,
                "oos": oos,
                "development_metrics": development_metrics,
                "oos_metrics": oos_metrics,
                "quality": quality,
                "total_profit": total_profit,
            })
        except (KeyError, OSError, UnicodeError, csv.Error, TypeError, ValueError):
            invalid += 1
    ranked.sort(key=lambda row: (-row["quality"], -row["total_profit"], str(row["item"].get("name", ""))))
    return ranked, invalid


def metric_grid(metrics: dict) -> str:
    return (
        f'<div><span>曲线分</span><strong>{metrics["score"]:.2f}</strong></div>'
        f'<div><span>最大余额回撤</span><strong>{metrics["max_dd_pct"]:.3f}%</strong></div>'
        f'<div><span>回撤痛苦指数</span><strong>{metrics["ulcer_pct"]:.3f}%</strong></div>'
        f'<div><span>最长连续亏损</span><strong>{metrics["max_loss_streak"]}次</strong></div>'
        f'<div><span>最深连续亏损</span><strong>{metrics["max_loss_run_pct"]:.3f}%</strong></div>'
        f'<div><span>上涨效率</span><strong>{metrics["upward_efficiency"]:.2f}%</strong></div>'
    )


def render(registry: dict, reports: pathlib.Path) -> str:
    ranked, invalid = rank_strategies(registry, reports)
    cards: list[str] = []
    for rank, row in enumerate(ranked, 1):
        item = row["item"]
        name = html.escape(str(item.get("name", "")))
        title = html.escape(str(item.get("chinese_name", name)))
        explanation = html.escape(str(item.get("explanation_zh", "")))
        source = html.escape(str(item.get("source_url", "#")))
        cards.append(f"""
<details class="strategy"><summary><span class="rank">#{rank}</span><span class="identity"><strong>{title}</strong><code>{name}</code></span>
<span class="headline"><b>曲线质量 {row['quality']:.2f}</b><em>总利润 {row['total_profit']:,.2f} USD</em></span></summary>
<div class="body"><div class="actions"><p>{explanation}</p><a href="{source}">下载MQL5源码</a></div>
<div class="totals"><div><span>开发区利润</span><strong>{float(item.get('profit',0)):,.2f}</strong></div>
<div><span>样本外利润</span><strong>{float(item.get('oos_profit',0)):,.2f}</strong></div>
<div><span>总利润</span><strong>{row['total_profit']:,.2f} USD</strong></div>
<div><span>开发区PF</span><strong>{float(item.get('profit_factor',0)):.3f}</strong></div>
<div><span>样本外PF</span><strong>{float(item.get('oos_profit_factor',0)):.3f}</strong></div></div>
<div class="totals"><div><span>开发区MT5最大权益回撤</span><strong>{float(item.get('equity_dd_pct',0)):.3f}%</strong></div>
<div><span>样本外MT5最大权益回撤</span><strong>{float(item.get('oos_equity_dd_pct',0)):.3f}%</strong></div></div>
<h3>开发区已实现余额曲线</h3><div class="metrics">{metric_grid(row['development_metrics'])}</div>
<div class="chart">{curve_svg(row['development'])}</div>
<h3>样本外已实现余额曲线</h3><div class="metrics">{metric_grid(row['oos_metrics'])}</div>
<div class="chart">{curve_svg(row['oos'])}</div></div></details>""")
    empty = '<div class="empty">尚无可排名的开发区与样本外双盈利策略</div>' if not cards else ""
    warning = f'<p class="warning">另有 {invalid} 个策略因资金曲线缺失或格式无效未参与排名。</p>' if invalid else ""
    return f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="60"><title>黄金策略资金曲线排名</title><style>
:root{{--ink:#13231c;--paper:#e9eee8;--card:#fffefa;--line:#c9d2ca;--green:#087f5b;--gold:#a96f00;--muted:#647069}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font:15px/1.55 "Microsoft YaHei",system-ui,sans-serif}}
main{{max-width:1240px;margin:auto;padding:34px 20px 70px}}header{{display:flex;justify-content:space-between;align-items:end;gap:20px;border-bottom:3px solid var(--ink);padding-bottom:18px}}
h1{{font:800 clamp(29px,5vw,54px)/1.03 Georgia,"Microsoft YaHei",serif;margin:0}}header a,.actions a{{background:var(--ink);color:#fff;padding:10px 15px;text-decoration:none;font-weight:700}}
.method{{background:#f9f5e8;border-left:6px solid var(--gold);padding:15px 18px;margin:20px 0}}.method strong{{color:var(--gold)}}
.strategy{{background:var(--card);border:1px solid var(--line);margin:14px 0;box-shadow:0 10px 28px #13231c0b}}summary{{display:flex;align-items:center;gap:16px;padding:18px 20px;cursor:pointer;list-style:none}}summary::-webkit-details-marker{{display:none}}summary:after{{content:"＋";font-size:24px}}details[open] summary:after{{content:"−"}}
.rank{{font:800 27px Georgia;color:var(--gold);width:58px}}.identity{{flex:1}}.identity strong,.identity code{{display:block}}.identity strong{{font-size:19px}}code{{color:#526159}}.headline{{display:flex;gap:18px;align-items:center}}.headline b{{color:var(--green);font-size:18px}}.headline em{{font-style:normal}}
.body{{border-top:1px solid var(--line);padding:20px}}.actions{{display:flex;justify-content:space-between;gap:20px;align-items:start}}.actions p{{margin:0;max-width:880px}}
.totals,.metrics{{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:1px;background:var(--line);border:1px solid var(--line);margin:18px 0}}.totals>div,.metrics>div{{background:#fff;padding:12px}}span{{display:block;color:var(--muted);font-size:12px}}strong{{font-size:18px}}
.chart{{background:#f5f7f2;border:1px solid var(--line);padding:8px}}svg{{display:block;width:100%;height:auto}}.curve{{fill:none;stroke:var(--green);stroke-width:4;stroke-linecap:round;stroke-linejoin:round}}.axis{{stroke:#aeb9b0}}svg text{{font-size:12px;fill:var(--muted)}}h3{{margin:25px 0 8px}}.empty,.warning{{padding:20px;background:#fff;border:1px solid var(--line)}}
@media(max-width:700px){{header,.actions{{display:block}}header a{{display:inline-block;margin-top:12px}}summary{{align-items:start;flex-wrap:wrap}}.headline{{width:100%;padding-left:74px;display:block}}.headline b,.headline em{{display:block}}}}
</style></head><body><main><header><div><div>REALIZED BALANCE QUALITY</div><h1>黄金策略资金曲线排名</h1></div><a href="/development-dashboard.html" target="_blank" rel="noopener">研发看板</a></header>
<div class="method"><strong>排序规则：</strong>先看曲线质量，样本外占60%、开发区占40%；惩罚最大余额回撤、回撤持续痛苦、连续亏损次数、连续亏损深度，并额外扣除MT5正式最大权益回撤风险，盈利向上跳跃不受惩罚。质量同分时再按开发区与样本外总利润排序。视觉角度会随图表缩放变化，因此不直接用“45度”做数学指标。</div>
<p class="method">图中CSV由MT5按平仓结果生成，准确名称是<strong>已实现余额曲线</strong>，不包含持仓过程中的浮动权益；最大权益回撤仍以MT5正式统计值为准。</p>
{warning}{empty}{''.join(cards)}</main></body></html>"""


def write_atomic(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        pathlib.Path(temporary_name).replace(path)
    except BaseException:
        pathlib.Path(temporary_name).unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    registry = load_json(pathlib.Path(args.registry))
    write_atomic(output, render(registry, output.parent))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
