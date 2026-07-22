from __future__ import annotations

import csv
import importlib.util
import pathlib
import tempfile
import unittest
import struct


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "render_ranked_strategy_dashboard.py"
SPEC = importlib.util.spec_from_file_location("ranked_dashboard", MODULE_PATH)
assert SPEC and SPEC.loader
RANKED = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RANKED)
PNG_MODULE_PATH = ROOT / "tools" / "render_balance_curve_png.py"
PNG_SPEC = importlib.util.spec_from_file_location("curve_png", PNG_MODULE_PATH)
assert PNG_SPEC and PNG_SPEC.loader
CURVE_PNG = importlib.util.module_from_spec(PNG_SPEC)
PNG_SPEC.loader.exec_module(CURVE_PNG)


def write_curve(path: pathlib.Path, values: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_msc", "balance"])
        for index, value in enumerate(values):
            writer.writerow([index, value])


def strategy(name: str, profit: float) -> dict:
    return {
        "name": name,
        "chinese_name": name,
        "explanation_zh": "test",
        "source_url": f"/published/{name}.mq5",
        "curve_file": f"published/{name}-development-equity.csv",
        "oos_curve_file": f"published/{name}-oos-equity.csv",
        "profit": profit,
        "oos_profit": profit,
        "profit_factor": 1.2,
        "oos_profit_factor": 1.2,
        "equity_dd_pct": 1.0,
        "oos_equity_dd_pct": 1.0,
    }


class CurveMetricTests(unittest.TestCase):
    def test_smooth_rise_beats_repeated_deep_drops(self) -> None:
        smooth = RANKED.curve_metrics([10000, 10020, 10040, 10060, 10080])
        rough = RANKED.curve_metrics([10000, 10200, 9900, 10300, 9800, 10400])
        self.assertGreater(smooth["score"], rough["score"])
        self.assertEqual(smooth["max_loss_streak"], 0)
        self.assertGreater(rough["max_dd_pct"], 0)

    def test_upward_profit_jump_is_not_penalized(self) -> None:
        steady = RANKED.curve_metrics([10000, 10020, 10040, 10060])
        jump = RANKED.curve_metrics([10000, 10020, 10500, 10520])
        self.assertEqual(steady["score"], jump["score"])

    def test_dependency_free_png_is_valid(self) -> None:
        data = CURVE_PNG.render([10000, 10020, 10010, 10050], (8, 127, 91))
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", data[16:24])
        self.assertEqual((width, height), (1200, 620))
        self.assertLess(len(data), 10 * 1024 * 1024)


class RankingTests(unittest.TestCase):
    def test_quality_precedes_profit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            reports = pathlib.Path(temporary)
            smooth = strategy("Smooth", 100)
            rough = strategy("Rough", 1000)
            for stage in ("development", "oos"):
                write_curve(reports / f"published/Smooth-{stage}-equity.csv", [10000, 10020, 10040, 10060])
                write_curve(reports / f"published/Rough-{stage}-equity.csv", [10000, 10500, 9700, 11000])
            ranked, invalid = RANKED.rank_strategies({"published": [rough, smooth]}, reports)
            self.assertEqual(invalid, 0)
            self.assertEqual(ranked[0]["item"]["name"], "Smooth")

    def test_render_uses_collapsed_cards_and_curves(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            reports = pathlib.Path(temporary)
            item = strategy("Alpha", 100)
            for stage in ("development", "oos"):
                write_curve(reports / f"published/Alpha-{stage}-equity.csv", [10000, 10020, 10040])
            document = RANKED.render({"published": [item]}, reports)
            self.assertIn('<details class="strategy">', document)
            self.assertNotIn('<details class="strategy" open', document)
            self.assertEqual(document.count('<polyline points="'), 2)
            self.assertIn("曲线质量", document)

    def test_official_equity_drawdown_reduces_rank_score(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            reports = pathlib.Path(temporary)
            low_risk = strategy("LowRisk", 100)
            high_risk = strategy("HighRisk", 200)
            high_risk["equity_dd_pct"] = 10.0
            high_risk["oos_equity_dd_pct"] = 10.0
            for name in ("LowRisk", "HighRisk"):
                for stage in ("development", "oos"):
                    write_curve(reports / f"published/{name}-{stage}-equity.csv", [10000, 10020, 10040])
            ranked, _ = RANKED.rank_strategies({"published": [high_risk, low_risk]}, reports)
            self.assertEqual(ranked[0]["item"]["name"], "LowRisk")


if __name__ == "__main__":
    unittest.main()
