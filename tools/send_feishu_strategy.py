#!/usr/bin/env python3
"""Send a detailed Chinese strategy notification and curve images to Feishu."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import tempfile
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from get_strategy_notification import rank_strategies, load_json
from render_balance_curve_png import load_balances, render


def request_json(
    url: str,
    payload: dict,
    token: str | None = None,
) -> dict:
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read(2000).decode("utf-8", errors="replace")
        raise RuntimeError(f"Feishu HTTP {error.code}: {detail}") from error
    if int(result.get("code", -1)) != 0:
        raise RuntimeError(f"Feishu rejected request: {result.get('code')} {result.get('msg')}")
    return result


def upload_image(path: pathlib.Path, token: str) -> str:
    boundary = f"----MT5GoldResearch{uuid.uuid4().hex}"
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"image_type\"\r\n\r\nmessage\r\n".encode(),
        (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; "
            f"filename=\"{path.name}\"\r\nContent-Type: image/png\r\n\r\n"
        ).encode(),
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    request = urllib.request.Request(
        "https://open.feishu.cn/open-apis/im/v1/images",
        data=b"".join(parts),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read(2000).decode("utf-8", errors="replace")
        raise RuntimeError(f"Feishu image upload HTTP {error.code}: {detail}") from error
    if int(result.get("code", -1)) != 0:
        raise RuntimeError(f"Feishu image upload failed: {result.get('code')} {result.get('msg')}")
    return str(result["data"]["image_key"])


def legacy_send(user_id: str, msg_type: str, content: dict, token: str) -> str:
    result = request_json(
        "https://open.feishu.cn/open-apis/message/v4/send/",
        {"user_id": user_id, "msg_type": msg_type, "content": content},
        token,
    )
    return str(result.get("data", {}).get("message_id", ""))


def format_metrics(label: str, item: dict, metrics: dict, prefix: str = "") -> list[str]:
    return [
        f"【{label}】",
        f"净利润：{float(item.get(prefix + 'profit', 0)):,.2f} USD",
        f"盈利因子：{float(item.get(prefix + 'profit_factor', 0)):.6f}",
        f"MT5最大权益回撤：{float(item.get(prefix + 'equity_dd_pct', 0)):.3f}%",
        f"曲线最大余额回撤：{float(metrics['max_dd_pct']):.3f}%",
        f"回撤痛苦指数：{float(metrics['ulcer_pct']):.3f}%",
        f"最长连续亏损：{int(metrics['max_loss_streak'])}次",
        f"最深连续亏损：{float(metrics['max_loss_run_pct']):.3f}%",
        f"上涨效率：{float(metrics['upward_efficiency']):.2f}%",
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--strategy-id", required=True)
    args = parser.parse_args()
    credentials = json.loads(pathlib.Path(args.credentials).read_text(encoding="utf-8-sig"))
    if credentials.get("receive_id_type") != "user_id" or not credentials.get("receive_id"):
        raise ValueError("Feishu user_id recipient is not configured")
    registry_path = pathlib.Path(args.registry)
    registry = load_json(registry_path)
    ranked, _ = rank_strategies(registry, registry_path.parent)
    selected = next(
        ((rank, row) for rank, row in enumerate(ranked, 1) if row["item"].get("name") == args.strategy_id),
        None,
    )
    if selected is None:
        raise ValueError("published strategy is not rankable")
    rank, row = selected
    item = row["item"]

    token_result = request_json(
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
        {"app_id": credentials["app_id"], "app_secret": credentials["app_secret"]},
    )
    token = str(token_result["tenant_access_token"])
    with tempfile.TemporaryDirectory() as temporary:
        temporary_path = pathlib.Path(temporary)
        development_png = temporary_path / f"{args.strategy_id}-development.png"
        oos_png = temporary_path / f"{args.strategy_id}-oos.png"
        development_png.write_bytes(render(row["development"], (8, 127, 91)))
        oos_png.write_bytes(render(row["oos"], (38, 91, 153)))
        development_key = upload_image(development_png, token)
        oos_key = upload_image(oos_png, token)

    lines = [
        f"黄金策略正式发布：{args.strategy_id}",
        f"中文名称：{item.get('chinese_name', '')}",
        f"资金曲线排名：第{rank}名 / {len(ranked)}个",
        f"综合曲线质量：{float(row['quality']):.2f}",
        f"开发区与样本外总利润：{float(row['total_profit']):,.2f} USD",
        f"父代：{item.get('parent_id', 'ROOT')}",
        f"策略逻辑：{item.get('explanation_zh', '')}",
        f"结构变化：{item.get('changes_zh', '')}",
        "",
        *format_metrics("开发区", item, row["development_metrics"]),
        f"交易日覆盖：{int(item.get('covered_days', 0))}/{int(item.get('active_days', 0))}，缺失{int(item.get('missing_days', 0))}天",
        "",
        *format_metrics("样本外", item, row["oos_metrics"], "oos_"),
        f"交易日覆盖：{int(item.get('oos_covered_days', 0))}/{int(item.get('oos_active_days', 0))}，缺失{int(item.get('oos_missing_days', 0))}天",
        "",
        "下面两张图片依次为开发区、样本外已实现余额曲线。",
    ]
    if credentials.get("ranking_url"):
        lines.append(f"资金曲线排名：{credentials['ranking_url']}")
    if credentials.get("dashboard_url"):
        lines.append(f"研发看板：{credentials['dashboard_url']}")
    message_ids = [
        legacy_send(str(credentials["receive_id"]), "text", {"text": "\n".join(lines)}, token),
        legacy_send(str(credentials["receive_id"]), "image", {"image_key": development_key}, token),
        legacy_send(str(credentials["receive_id"]), "image", {"image_key": oos_key}, token),
    ]
    print(json.dumps({"strategy_id": args.strategy_id, "message_ids": message_ids}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
