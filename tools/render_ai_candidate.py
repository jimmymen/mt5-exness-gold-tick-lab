#!/usr/bin/env python3
"""Render one validated candidate spec through the fixed MQL5 template."""

from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import re


generator_path = pathlib.Path(__file__).with_name("generate_ai_candidate.py")
generator_spec = importlib.util.spec_from_file_location("generate_ai_candidate", generator_path)
if generator_spec is None or generator_spec.loader is None:
    raise RuntimeError("unable to load candidate generator")
generator = importlib.util.module_from_spec(generator_spec)
generator_spec.loader.exec_module(generator)
BOOLEAN_FIELDS = generator.BOOLEAN_FIELDS
FLOAT_LIMITS = generator.FLOAT_LIMITS
INTEGER_LIMITS = generator.INTEGER_LIMITS
render = generator.render


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", required=True)
    parser.add_argument("--spec", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    spec = json.loads(pathlib.Path(args.spec).read_text(encoding="utf-8-sig"))
    candidate_id = str(spec.get("id", ""))
    if not re.fullmatch(r"AIResearch\d{4}", candidate_id):
        raise ValueError("invalid candidate ID")
    required = set(INTEGER_LIMITS) | set(FLOAT_LIMITS) | BOOLEAN_FIELDS
    if not required <= spec.keys():
        raise ValueError(f"missing strategy fields: {sorted(required - spec.keys())}")
    for key, (low, high) in INTEGER_LIMITS.items():
        if not low <= int(spec[key]) <= high:
            raise ValueError(f"{key} outside allowed range")
    for key, (low, high) in FLOAT_LIMITS.items():
        if not low <= float(spec[key]) <= high:
            raise ValueError(f"{key} outside allowed range")
    for key in BOOLEAN_FIELDS:
        if not isinstance(spec[key], bool):
            raise ValueError(f"{key} must be boolean")

    template = pathlib.Path(args.template).read_text(encoding="utf-8")
    source = render(template, spec)
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(source, encoding="ascii", errors="strict")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
