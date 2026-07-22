#!/usr/bin/env python3
"""Use AI evaluation feedback to design and render the next safe MQL5 generation."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import ssl
import urllib.error
import urllib.request


INTEGER_LIMITS = {
    "signal_a_type": (0, 5), "signal_a_period": (1, 60), "signal_a_weight": (1, 4),
    "signal_b_type": (0, 5), "signal_b_period": (1, 60), "signal_b_weight": (1, 4),
    "signal_c_type": (0, 5), "signal_c_period": (1, 60), "signal_c_weight": (1, 4),
    "regime_mode": (0, 2), "hold_hours": (1, 23), "atr_period": (7, 40),
}
FLOAT_LIMITS = {
    "stop_atr": (1.0, 6.0), "target_atr": (0.0, 8.0), "trail_atr": (0.0, 6.0),
}
BOOLEAN_FIELDS = {"signal_a_invert", "signal_b_invert", "signal_c_invert"}
TEXT_FIELDS = {
    "chinese_name": 50,
    "explanation_zh": 500,
    "failure_analysis_zh": 800,
    "hypothesis_zh": 800,
    "changes_zh": 500,
    "parent_id": 30,
}


def validate(spec: dict, attempted: int) -> dict:
    required = set(INTEGER_LIMITS) | set(FLOAT_LIMITS) | BOOLEAN_FIELDS | set(TEXT_FIELDS)
    if not required <= spec.keys():
        raise ValueError(f"missing fields: {sorted(required - spec.keys())}")
    for key, (low, high) in INTEGER_LIMITS.items():
        value = int(spec[key])
        if not low <= value <= high:
            raise ValueError(f"{key} outside [{low}, {high}]")
        spec[key] = value
    for key, (low, high) in FLOAT_LIMITS.items():
        value = round(float(spec[key]), 2)
        if not low <= value <= high:
            raise ValueError(f"{key} outside [{low}, {high}]")
        spec[key] = value
    for key in BOOLEAN_FIELDS:
        if not isinstance(spec[key], bool):
            raise ValueError(f"{key} must be boolean")
    for key, limit in TEXT_FIELDS.items():
        spec[key] = str(spec[key]).strip()[:limit]
        if not spec[key]:
            raise ValueError(f"{key} must not be empty")
    spec["id"] = f"AIResearch{attempted + 1:04d}"
    spec["generated_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    return spec


def strategy_signature(spec: dict) -> tuple:
    fields = [*INTEGER_LIMITS, *FLOAT_LIMITS, *sorted(BOOLEAN_FIELDS)]
    return tuple(spec.get(key) for key in fields)


def request_spec(credentials: dict, registry: dict) -> dict:
    attempted = int(registry.get("attempted", 0))
    prior_specs = registry.get("attempted_specs", [])
    evaluations = registry.get("evaluations", [])
    compact_evaluations = evaluations[-12:]
    compact_specs = [
        {key: item.get(key) for key in ["id", *INTEGER_LIMITS, *FLOAT_LIMITS, *BOOLEAN_FIELDS]}
        for item in prior_specs[-20:]
    ]
    prompt = (
        "你负责完整的黄金量化策略代际研发。根据历史候选的开发区和样本外结果，先分析失败原因，"
        "再提出可证伪的下一代假设，并设计结构变化。每天必须交易一次由执行模板强制。"
        "只返回JSON对象，不要Markdown。信号类型：0=N日动量，1=前一日K线方向，"
        "2=收盘相对EMA，3=RSI相对50，4=N日区间中点，5=N日累计变化。"
        "regime_mode：0=三信号始终加权；1=高波动用A+B、低波动用B+C；"
        "2=低波动用A+B、高波动用B+C。target_atr或trail_atr为0表示关闭。"
        "必须返回字段：chinese_name, explanation_zh, failure_analysis_zh, hypothesis_zh, "
        "changes_zh, parent_id, signal_a_type, signal_a_period, signal_a_invert, signal_a_weight, "
        "signal_b_type, signal_b_period, signal_b_invert, signal_b_weight, signal_c_type, "
        "signal_c_period, signal_c_invert, signal_c_weight, regime_mode, hold_hours, atr_period, "
        "stop_atr, target_atr, trail_atr。信号period 1-60，weight 1-4，hold_hours 1-23，"
        "atr_period 7-40，stop_atr 1-6，target_atr 0-8，trail_atr 0-6。"
        "parent_id应引用你主要改进的历史候选；若没有则写ROOT。不要重复已测结构。\n"
        "最近评估结果：" + json.dumps(compact_evaluations, ensure_ascii=False) + "\n"
        "最近已测结构：" + json.dumps(compact_specs, ensure_ascii=False)
    )
    payload = {
        "model": credentials["model"],
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是严谨的量化研发负责人。必须利用失败证据提出下一代逻辑，"
                    "不能只随机改参数；只输出合法JSON。"
                ),
            },
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.7,
        "response_format": {"type": "json_object"},
    }
    if credentials.get("thinking"):
        payload["thinking"] = {"type": "enabled"}
    if credentials.get("reasoning_effort"):
        payload["reasoning_effort"] = credentials["reasoning_effort"]
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        credentials["base_url"].rstrip("/") + "/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {credentials['api_key']}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        ca_file = credentials.get("ca_file")
        context = ssl.create_default_context(cafile=ca_file) if ca_file else ssl.create_default_context()
        with urllib.request.urlopen(request, timeout=120, context=context) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read(1000).decode(errors="replace")
        raise RuntimeError(f"AI HTTP {error.code}: {detail}") from error
    content = payload["choices"][0]["message"]["content"].strip()
    match = re.search(r"\{.*\}", content, re.DOTALL)
    if not match:
        raise ValueError("AI response did not contain a JSON object")
    spec = validate(json.loads(match.group(0)), attempted)
    signatures = {strategy_signature(item) for item in prior_specs}
    if strategy_signature(spec) in signatures:
        raise ValueError("AI returned an already tested strategy structure")
    return spec


def render(template: str, spec: dict) -> str:
    replacements = {
        "29000001": str(29000000 + int(spec["id"][-4:])),
        "InpSignalAType = 0": f"InpSignalAType = {spec['signal_a_type']}",
        "InpSignalAPeriod = 5": f"InpSignalAPeriod = {spec['signal_a_period']}",
        "InpSignalAInvert = false": f"InpSignalAInvert = {str(spec['signal_a_invert']).lower()}",
        "InpSignalAWeight = 2": f"InpSignalAWeight = {spec['signal_a_weight']}",
        "InpSignalBType = 1": f"InpSignalBType = {spec['signal_b_type']}",
        "InpSignalBPeriod = 3": f"InpSignalBPeriod = {spec['signal_b_period']}",
        "InpSignalBInvert = false": f"InpSignalBInvert = {str(spec['signal_b_invert']).lower()}",
        "InpSignalBWeight = 1": f"InpSignalBWeight = {spec['signal_b_weight']}",
        "InpSignalCType = 2": f"InpSignalCType = {spec['signal_c_type']}",
        "InpSignalCPeriod = 20": f"InpSignalCPeriod = {spec['signal_c_period']}",
        "InpSignalCInvert = false": f"InpSignalCInvert = {str(spec['signal_c_invert']).lower()}",
        "InpSignalCWeight = 1": f"InpSignalCWeight = {spec['signal_c_weight']}",
        "InpRegimeMode = 0": f"InpRegimeMode = {spec['regime_mode']}",
        "InpHoldHours = 8": f"InpHoldHours = {spec['hold_hours']}",
        "InpAtrPeriod = 14": f"InpAtrPeriod = {spec['atr_period']}",
        "InpStopAtrMultiple = 2.0": f"InpStopAtrMultiple = {spec['stop_atr']}",
        "InpTargetAtrMultiple = 0.0": f"InpTargetAtrMultiple = {spec['target_atr']}",
        "InpTrailAtrMultiple = 0.0": f"InpTrailAtrMultiple = {spec['trail_atr']}",
        'InpOutputName = "AdaptiveDailyStrategy"': f'InpOutputName = "{spec["id"]}"',
        "AdaptiveDailyStrategy": spec["id"],
    }
    for old, new in replacements.items():
        template = template.replace(old, new)
    return template


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--output-directory", required=True)
    parser.add_argument("--spec-output", required=True)
    args = parser.parse_args()
    credentials = json.loads(pathlib.Path(args.credentials).read_text(encoding="utf-8-sig"))
    registry = json.loads(pathlib.Path(args.registry).read_text(encoding="utf-8-sig"))
    spec = request_spec(credentials, registry)
    source = render(pathlib.Path(args.template).read_text(encoding="utf-8"), spec)
    output = pathlib.Path(args.output_directory) / f"{spec['id']}.mq5"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(source, encoding="ascii", errors="strict")
    pathlib.Path(args.spec_output).write_text(json.dumps(spec, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"source": str(output), "spec": spec}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
