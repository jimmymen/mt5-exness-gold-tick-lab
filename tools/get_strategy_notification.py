#!/usr/bin/env python3
"""Return detailed ranking and curve metadata for one published strategy."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from render_ranked_strategy_dashboard import load_json, rank_strategies


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--strategy-id", required=True)
    args = parser.parse_args()
    registry_path = pathlib.Path(args.registry)
    ranked, _ = rank_strategies(load_json(registry_path), registry_path.parent)
    for rank, row in enumerate(ranked, 1):
        item = row["item"]
        if str(item.get("name")) != args.strategy_id:
            continue
        result = {
            "rank": rank,
            "quality": row["quality"],
            "total_profit": row["total_profit"],
            "development_metrics": row["development_metrics"],
            "oos_metrics": row["oos_metrics"],
            "development_curve": str(registry_path.parent / str(item["curve_file"])),
            "oos_curve": str(registry_path.parent / str(item["oos_curve_file"])),
            "chinese_name": item.get("chinese_name", ""),
            "explanation_zh": item.get("explanation_zh", ""),
            "changes_zh": item.get("changes_zh", ""),
            "parent_id": item.get("parent_id", "ROOT"),
        }
        print(json.dumps(result, ensure_ascii=False))
        return 0
    raise SystemExit(f"published strategy not found or unrankable: {args.strategy_id}")


if __name__ == "__main__":
    raise SystemExit(main())
