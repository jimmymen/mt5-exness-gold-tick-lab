@echo off
"C:\Tools\Python312\python.exe" "C:\QuantResearch\mt5-gold-research\tools\normalize_exness_tick_archives.py" --root "C:\QuantResearch\tick-data\exness\XAUUSDm" --years 2021 2022 2023 2024 2025 2026 --monthly 1>"C:\QuantResearch\tick-data\exness\XAUUSDm\normalize.stdout.log" 2>"C:\QuantResearch\tick-data\exness\XAUUSDm\normalize.stderr.log"
