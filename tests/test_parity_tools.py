from __future__ import annotations

import csv
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
COMPARE = ROOT / "tools" / "compare_parity_runs.py"
RENDER = ROOT / "tools" / "render_development_dashboard.py"


def write_csv(path: pathlib.Path, rows: list[list[str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        csv.writer(handle).writerows(rows)


class ParityComparatorTests(unittest.TestCase):
    def make_fixture(self, directory: pathlib.Path) -> None:
        summary = [
            ["key", "value"], ["run_label", "auto"], ["symbol", "XAUUSDm"],
            ["terminal_build", "5836"], ["ticks", "2"], ["first_msc", "1"],
            ["last_msc", "2"], ["initial", "10000.00"], ["balance", "10001.00"],
            ["profit", "1.00"], ["profit_factor", "2.00"],
            ["balance_dd_pct", "0.1"], ["equity_dd_pct", "0.2"],
            ["trades", "1"], ["deals", "2"],
        ]
        daily = [
            ["day_utc", "ticks", "first_msc", "last_msc", "time_sum_mod", "bid_points_sum", "ask_points_sum"],
            ["20260713", "2", "1", "2", "3", "400000", "400010"],
        ]
        deals = [
            ["index", "time_msc", "type", "entry", "volume", "price", "commission", "swap", "profit"],
            ["0", "1", "0", "0", "0.01", "4000.000", "0", "0", "1"],
        ]
        for label in ("auto", "gui"):
            label_summary = [row.copy() for row in summary]
            label_summary[1][1] = label
            write_csv(directory / f"{label}-summary.csv", label_summary)
            write_csv(directory / f"{label}-daily.csv", daily)
            write_csv(directory / f"{label}-deals.csv", deals)

    def run_comparator(self, directory: pathlib.Path) -> tuple[int, dict]:
        output = directory / "result.json"
        process = subprocess.run(
            [sys.executable, str(COMPARE), "--directory", str(directory), "--output", str(output)],
            check=False,
            capture_output=True,
            text=True,
        )
        return process.returncode, json.loads(output.read_text(encoding="utf-8"))

    def test_identical_artifacts_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            self.make_fixture(directory)
            code, result = self.run_comparator(directory)
            self.assertEqual(code, 0)
            self.assertEqual(result["gate"], "ALIGNMENT PASSED")
            self.assertIn("generated_utc", result)

    def test_deal_difference_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            self.make_fixture(directory)
            write_csv(
                directory / "gui-deals.csv",
                [["index", "time_msc", "type", "entry", "volume", "price", "commission", "swap", "profit"],
                 ["0", "1", "0", "0", "0.01", "4000.001", "0", "0", "1"]],
            )
            code, result = self.run_comparator(directory)
            self.assertEqual(code, 1)
            self.assertEqual(result["gate"], "ALIGNMENT FAILED")
            self.assertFalse(result["checks"][2]["passed"])

    def test_duplicate_summary_key_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            self.make_fixture(directory)
            write_csv(
                directory / "gui-summary.csv",
                [["key", "value"], ["run_label", "gui"], ["ticks", "2"], ["ticks", "2"]],
            )
            code, result = self.run_comparator(directory)
            self.assertEqual(code, 2)
            self.assertEqual(result["gate"], "ALIGNMENT BLOCKED")
            self.assertIn("duplicate summary key", result["errors"][0])

    def test_missing_artifacts_block(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            code, result = self.run_comparator(directory)
            self.assertEqual(code, 2)
            self.assertEqual(len(result["missing"]), 6)

    def test_empty_daily_evidence_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            self.make_fixture(directory)
            header = ["day_utc", "ticks", "first_msc", "last_msc", "time_sum_mod", "bid_points_sum", "ask_points_sum"]
            write_csv(directory / "gui-daily.csv", [header])
            code, result = self.run_comparator(directory)
            self.assertEqual(code, 2)
            self.assertEqual(result["gate"], "ALIGNMENT BLOCKED")

    def test_wrong_run_label_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            self.make_fixture(directory)
            path = directory / "gui-summary.csv"
            with path.open(encoding="utf-8") as handle:
                rows = list(csv.reader(handle))
            rows[1][1] = "auto"
            write_csv(path, rows)
            code, result = self.run_comparator(directory)
            self.assertEqual(code, 2)
            self.assertIn("run_label", result["errors"][0])


class DashboardTests(unittest.TestCase):
    def test_stale_worker_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            state = directory / "state.json"
            parity = directory / "parity.json"
            output = directory / "dashboard.html"
            state.write_text(
                json.dumps({"phase": "research", "message": "running", "updated_utc": "2020-01-01T00:00:00+00:00"}),
                encoding="utf-8",
            )
            parity.write_text(
                json.dumps({"status": "passed", "gate": "ALIGNMENT PASSED", "checks": []}),
                encoding="utf-8",
            )
            subprocess.run(
                [
                    sys.executable,
                    str(RENDER),
                    "--state",
                    str(state),
                    "--parity",
                    str(parity),
                    "--output",
                    str(output),
                ],
                check=True,
            )
            self.assertIn("研发进程心跳已中断", output.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
